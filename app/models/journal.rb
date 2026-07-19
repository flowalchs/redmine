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

class Journal < ApplicationRecord
  include Redmine::SafeAttributes
  include Redmine::Reaction::Reactable

  belongs_to :journalized, :polymorphic => true, :inverse_of => :journals
  belongs_to :user
  belongs_to :updated_by, :class_name => 'User'

  has_many :details, :class_name => "JournalDetail", :dependent => :delete_all, :inverse_of => :journal
  attr_accessor :indice

  cattr_accessor :journalized_types

  def self.register_journalized_type(klass)
    self.journalized_types ||= []
    self.journalized_types << klass unless journalized_types.include?(klass)
  end

  def self.activity_scope_for(klass)
    scope = where(journalized_type: klass.name)
    scope = scope.preload(*klass.journal_activity_preload)
    klass.journal_activity_scope(scope)
  end

  def self.register_activity_provider(klass)
    return if klass.journal_activity_type.blank?

    acts_as_activity_provider(
      type: klass.journal_activity_type,
      author_key: :user_id,
      scope: proc { activity_scope_for(klass) }
    )
  end

  acts_as_event(
    title: proc {|o|  o.journalized.journal_event_title(o) },
    description: :notes,
    author: :user,
    group: :journalized,
    type: proc {|o| o.journalized.journal_event_type(o) },
    url: proc {|o| o.journalized.journal_event_url(o) }
  )
  acts_as_mentionable :attributes => ['notes']
  before_create :split_private_notes
  before_create :add_watcher
  after_create_commit :send_notification

  scope :visible, (lambda do |*args|
    user = args.shift || User.current
    options = args.shift || {}
    visible_scope = none

    journalized_types.each do |klass|
      relation = where(journalized_type: klass.name)
      relation = klass.journal_visibility_scope(relation)
      relation = relation.where(journalized_id: klass.journal_visible_scope(user, options).select(:id))
      relation = klass.journal_notes_visibility_scope(relation, user, options)
      visible_scope = visible_scope.or(relation)
    end
    visible_scope
  end)

  safe_attributes(
    'notes',
    :if => lambda {|journal, user| journal.new_record? || journal.editable_by?(user)})
  safe_attributes(
    'private_notes',
    :if => lambda {|journal, user| journal.journalized.journal_private_notes_allowed?(user)})
  safe_attributes 'updated_by'

  # Returns a SQL condition to filter out journals with notes that are not visible to user
  def self.visible_notes_condition(user=User.current, options={})
    private_notes_permission = Project.allowed_to_condition(user, :view_private_notes, options)
    sanitize_sql_for_conditions(["(#{table_name}.private_notes = ? OR #{table_name}.user_id = ? OR (#{private_notes_permission}))", false, user.id])
  end

  def initialize(*args)
    super
    if journalized
      if journalized.new_record?
        self.notify = false
      else
        start
      end
    end
  end

  def save(*args)
    journalize_changes
    # Do not save an empty journal
    (new_record? && notes_and_details_empty?) ? false : super()
  end

  def notes_and_details_empty?
    notes.blank? && details.empty?
  end

  # Returns journal details that are visible to user
  def visible_details(user=User.current)
    details.select do |detail|
      if detail.property == 'cf'
        detail.custom_field && detail.custom_field.visible_by?(project, user)
      elsif detail.property == 'relation'
        journalized.journal_relation_visible?(detail, user)
      else
        true
      end
    end
  end

  # Returns the JournalDetail for the given attribute, or nil if the attribute
  # was not updated
  def detail_for_attribute(attribute)
    details.detect {|detail| detail.prop_key == attribute}
  end

  def new_status
    journalized.journal_new_status(self)
  end

  def new_value_for(prop)
    detail_for_attribute(prop).try(:value)
  end

  def editable_by?(usr)
    journalized.journal_editable_by?(self, usr)
  end

  def project
    journalized.journal_project
  end

  def attachments
    @attachments ||= begin
      ids = details.select {|d| d.property == 'attachment' && d.value.present?}.map(&:prop_key)
      ids.empty? ? [] : Attachment.where(id: ids).sort_by {|a| ids.index(a.id.to_s)}
    end
  end

  def visible?(*)
    journalized.journal_visible?(*)
  end

  def attachments_visible?
    journalized&.attachments_visible?
  end

  # Returns a string of css classes
  def css_classes
    s = +'journal'
    s << ' has-notes' unless notes.blank?
    s << ' has-details' unless details.blank?
    s << ' private-notes' if private_notes?
    s
  end

  def notify?
    @notify != false
  end

  def notify=(arg)
    @notify = arg
  end

  def notified_users
    notified = journalized.journal_notified_users
    if private_notes?
      notified = select_journal_visible_user(notified)
    end
    notified
  end

  def recipients
    notified_users.map(&:mail)
  end

  def notified_watchers
    notified = journalized.journal_notified_watchers
    select_journal_visible_user(notified)
  end

  def notified_mentions
    notified = super
    select_journal_visible_user(notified)
  end

  def watcher_recipients
    notified_watchers.map(&:mail)
  end

  # Sets @custom_field instance variable on journals details using a single query
  def self.preload_journals_details_custom_fields(journals)
    field_ids = journals.map(&:details).flatten.select {|d| d.property == 'cf'}.map(&:prop_key).uniq
    if field_ids.any?
      fields_by_id = CustomField.where(:id => field_ids).index_by { |f| f.id }
      journals.each do |journal|
        journal.details.each do |detail|
          if detail.property == 'cf'
            detail.instance_variable_set :@custom_field, fields_by_id[detail.prop_key.to_i]
          end
        end
      end
    end
    journals
  end

  # Stores the values of the attributes and custom fields of the journalized object
  def start
    if journalized
      @attributes_before_change = journalized.journalized_attribute_names.index_with do |attribute|
        journalized.send(attribute)
      end
      @custom_values_before_change = journalized.custom_field_values.to_h do |c|
        [c.custom_field_id, c.value]
      end
    end
    self
  end

  # Adds a journal detail for an attachment that was added or removed
  def journalize_attachment(attachment, added_or_removed)
    key = (added_or_removed == :removed ? :old_value : :value)
    details <<
      JournalDetail.new(
        :property => 'attachment',
        :prop_key => attachment.id,
        key => attachment.filename
      )
  end

  # Adds a journal detail for an issue relation that was added or removed
  def journalize_relation(relation, added_or_removed)
    key = (added_or_removed == :removed ? :old_value : :value)
    details <<
      JournalDetail.new(
        :property  => 'relation',
        :prop_key  => relation.relation_type_for(journalized),
        key => relation.other_issue(journalized).try(:id)
      )
  end

  def valid_watcher?(user)
    journalized.journal_valid_watcher?(user)
  end

  private

  # Generates journal details for attribute and custom field changes
  def journalize_changes
    # attributes changes
    if @attributes_before_change
      attrs = (journalized.journalized_attribute_names + @attributes_before_change.keys).uniq
      attrs.each do |attribute|
        before = @attributes_before_change[attribute]
        after = journalized.send(attribute)
        next if before == after || (before.blank? && after.blank?)

        add_attribute_detail(attribute, before, after)
      end
    end
    # custom fields changes
    if @custom_values_before_change
      values_by_custom_field_id = {}
      @custom_values_before_change.each_key do |custom_field_id|
        values_by_custom_field_id[custom_field_id] = nil
      end
      journalized.custom_field_values.each do |c|
        values_by_custom_field_id[c.custom_field_id] = c.value
      end

      values_by_custom_field_id.each do |custom_field_id, after|
        before = @custom_values_before_change[custom_field_id]
        next if before == after || (before.blank? && after.blank?)

        if before.is_a?(Array) || after.is_a?(Array)
          before = [before] unless before.is_a?(Array)
          after = [after] unless after.is_a?(Array)

          # values removed
          (before - after).reject(&:blank?).each do |value|
            add_custom_field_detail(custom_field_id, value, nil)
          end
          # values added
          (after - before).reject(&:blank?).each do |value|
            add_custom_field_detail(custom_field_id, nil, value)
          end
        else
          add_custom_field_detail(custom_field_id, before, after)
        end
      end
    end
    start
  end

  # Adds a journal detail for an attribute change
  def add_attribute_detail(attribute, old_value, value)
    add_detail('attr', attribute, old_value, value)
  end

  # Adds a journal detail for a custom field value change
  def add_custom_field_detail(custom_field_id, old_value, value)
    add_detail('cf', custom_field_id, old_value, value)
  end

  # Adds a journal detail
  def add_detail(property, prop_key, old_value, value)
    details <<
      JournalDetail.new(
        :property => property,
        :prop_key => prop_key,
        :old_value => old_value,
        :value => value
      )
  end

  def split_private_notes
    if private_notes?
      if notes.present?
        if details.any?
          # Split the journal (notes/changes) so we don't have half-private journals
          journal = Journal.new(:journalized => journalized, :user => user, :notes => nil, :private_notes => false)
          journal.details = details
          journal.save
          self.details = []
          self.created_on = journal.created_on
        end
      else
        # Blank notes should not be private
        self.private_notes = false
      end
    end
    true
  end

  def add_watcher
    journalized.journal_process_watchers(self)
  end

  def send_notification
    journalized.journal_notify(self)
  end

  def select_journal_visible_user(notified)
    if private_notes?
      notified = notified.select {|user| journalized.journal_user_can_view_private_notes?(user)}
    end
    notified
  end
end
