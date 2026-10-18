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

require_relative '../../../../test_helper'

class Redmine::Acts::JournalizedTest < ActiveSupport::TestCase
  def setup
    User.current = nil
    # Use News as a second journalized type
    News.acts_as_journalized unless News.respond_to?(:journalized_options)
    @news_registered = Redmine::Acts::Journalized.journalized_type_names.include?('News')
    Redmine::Acts::Journalized.register('News')
    @news = News.find(1)
  end

  def teardown
    Redmine::Acts::Journalized.unregister('News') unless @news_registered
  end

  def test_issue_should_be_registered
    assert_include 'Issue', Redmine::Acts::Journalized.journalized_type_names
    assert_include Issue, Redmine::Acts::Journalized.journalized_classes
  end

  def test_acts_as_journalized_should_reject_invalid_options
    assert_raise ArgumentError do
      Class.new(ApplicationRecord) { acts_as_journalized :foo => 'bar' }
    end
  end

  def test_visible_should_include_journals_of_each_journalized_type
    journal = Journal.create!(:journalized => @news, :user => User.find(2), :notes => 'News note')
    journals = Journal.visible(User.anonymous)

    assert_include journal, journals
    assert journals.where(:journalized_type => 'Issue').exists?
    assert_equal Journal.where(:journalized_type => 'Issue').visible(User.anonymous).sort,
                 journals.where(:journalized_type => 'Issue').sort
  end

  def test_visible_should_not_include_journals_of_invisible_records
    journal = Journal.create!(:journalized => @news, :user => User.find(2), :notes => 'News note')
    Role.anonymous.remove_permission!(:view_news)

    assert_not_include journal, Journal.visible(User.anonymous)
    assert_not journal.visible?(User.anonymous)
  end

  def test_visible_should_not_include_private_notes_without_permission
    journal = Journal.create!(:journalized => @news, :user => User.find(2), :notes => 'Private', :private_notes => true)

    assert_not_include journal, Journal.visible(User.anonymous)
    assert_include journal, Journal.visible(User.find(2))
    assert_include journal, Journal.visible(User.find(1))
  end

  def test_notified_users_should_exclude_users_not_allowed_to_view_private_notes
    journal = Journal.new(:journalized => @news, :user => User.find(2), :notes => 'Private', :private_notes => true)
    Role.find(1).remove_permission!(:view_private_notes)

    assert journal.notified_users.none? {|user| user.roles_for_project(@news.project).include?(Role.find(1)) && !user.admin?}
  end

  def test_editable_by_should_check_configured_permission
    journal = Journal.create!(:journalized => @news, :user => User.find(2), :notes => 'News note')

    assert journal.editable_by?(User.find(2))
    Role.find(1).remove_permission!(:manage_news)
    assert_not journal.editable_by?(User.find(2))
  end

  def test_visible_should_join_journalized_table_when_restricted_to_one_type
    sql = Journal.where(:journalized_type => 'Issue').visible(User.anonymous).to_sql
    assert_include 'INNER JOIN issues', sql
    assert_not_include 'EXISTS (SELECT 1 FROM "issues"', sql
  end

  def test_visible_should_use_exists_conditions_for_several_types
    sql = Journal.visible(User.anonymous).to_sql
    assert_not_include 'INNER JOIN issues', sql
    assert_include "journals.journalized_type = 'News' AND EXISTS", sql
  end

  def test_visible_with_join_and_exists_conditions_should_return_the_same_issue_journals
    user = User.find(2)
    assert_equal Journal.where(:journalized_type => 'Issue').visible(user).ids.sort,
                 Journal.where(:journalized_type => 'Issue').where(Issue.journal_visible_condition(user)).ids.sort
  end

  def test_news_journals_should_be_activity_events
    journal = Journal.create!(:journalized => @news, :user => User.find(2), :notes => 'News note')
    fetcher = Redmine::Activity::Fetcher.new(User.find(2), :project => @news.project)

    assert_include journal, fetcher.events(nil, nil)
    assert_equal 'News: eCookbook first release !', journal.event_title
    assert_equal({:controller => 'news', :action => 'show', :id => 1, :anchor => "change-#{journal.id}"}, journal.event_url)
    assert fetcher.events(nil, nil, :last_by_project => true).any?
  end

  def test_joins_journalized_should_join_journalized_table_and_project
    journals = Journal.joins_journalized(Issue).where(:issues => {:project_id => 1})

    assert journals.any?
    assert journals.all? {|journal| journal.journalized.is_a?(Issue) && journal.project.id == 1}
  end
end
