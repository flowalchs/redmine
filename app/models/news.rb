# frozen_string_literal: true

# Redmine - project management software
# Copyright (C) 2006-  Jean-Philippe Lang
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

class News < ApplicationRecord
  include Redmine::SafeAttributes
  include Redmine::Reaction::Reactable

  belongs_to :project
  belongs_to :author, :class_name => 'User'
  has_many :comments, lambda {order(:created_on)}, :as => :commented, :dependent => :delete_all

  validates_presence_of :title, :description
  validates_length_of :title, :maximum => 60
  validates_length_of :summary, :maximum => 255

  acts_as_attachable :edit_permission => :manage_news,
                     :delete_permission => :manage_news,
                     :after_add => :attachment_added,
                     :after_remove => :attachment_removed
  acts_as_searchable :columns => ['title', 'summary', "#{table_name}.description"],
                     :preload => :project
  acts_as_event :url => Proc.new {|o| {:controller => 'news', :action => 'show', :id => o.id}}
  acts_as_activity_provider :scope => proc {preload(:project, :author)},
                            :author_key => :author_id
  acts_as_watchable
  acts_as_webhookable
  acts_as_journalized :activity_type => 'news',
                      :attributes => %w(title summary description),
                      :permissions => {
                        :edit_notes => :manage_news,
                        :add_watchers => :manage_news
                      }
  include News::Webhookable

  after_create :add_author_as_watcher
  after_create_commit :send_notification
  after_save :create_journal

  scope :visible, (lambda do |*args|
    joins(:project).
    where(Project.allowed_to_condition(args.shift || User.current, :view_news, *args))
  end)

  safe_attributes 'title', 'summary', 'description'

  def visible?(user=User.current)
    !user.nil? && user.allowed_to?(:view_news, project)
  end

  def init_journal(user, notes = '')
    @current_journal ||= Journal.new(:journalized => self, :user => user, :notes => notes)
  end

  attr_reader :current_journal

  # Callback on file attachment
  def attachment_added(attachment)
    if current_journal && !attachment.new_record?
      current_journal.journalize_attachment(attachment, :added)
    end
  end

  # Callback on attachment deletion
  def attachment_removed(attachment)
    if current_journal && !attachment.new_record?
      current_journal.journalize_attachment(attachment, :removed)
      current_journal.save
    end
  end

  def journal_event_title(journal)
    "#{l(:label_news)}: #{title}"
  end

  def journal_event_type(journal)
    'news'
  end

  # Returns true if the news can be commented by user
  def commentable?(user=User.current)
    user.allowed_to?(:comment_news, project)
  end

  def notified_users
    project.users.select {|user| user.notify_about?(self) && user.allowed_to?(:view_news, project)}
  end

  def recipients
    notified_users.map(&:mail)
  end

  # Returns the users that should be cc'd when a new news is added
  def notified_watchers_for_added_news
    watchers = []
    if m = project.enabled_module('news')
      watchers = m.notified_watchers
      unless project.is_public?
        watchers = watchers.select {|user| project.users.include?(user)}
      end
    end
    watchers
  end

  # Returns the email addresses that should be cc'd when a new news is added
  def cc_for_added_news
    notified_watchers_for_added_news.map(&:mail)
  end

  # returns latest news for projects visible by user
  def self.latest(user = User.current, count = 5)
    visible(user).preload(:author, :project).order("#{News.table_name}.created_on DESC").limit(count).to_a
  end

  private

  def create_journal
    current_journal&.save
    @current_journal = nil
  end

  def add_author_as_watcher
    Watcher.create(:watchable => self, :user => author)
  end

  def send_notification
    if Setting.notified_events.include?('news_added')
      Mailer.deliver_news_added(self)
    end
  end
end
