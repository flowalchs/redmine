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
    Redmine::Acts::Journalized.register('News')
    @news = News.find(1)
  end

  def teardown
    Redmine::Acts::Journalized.unregister('News')
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

  def test_editable_by_should_be_false_without_configured_permission
    journal = Journal.create!(:journalized => @news, :user => User.find(2), :notes => 'News note')

    assert_not journal.editable_by?(User.find(2))
  end

  def test_joins_journalized_should_join_journalized_table_and_project
    journals = Journal.joins_journalized(Issue).where(:issues => {:project_id => 1})

    assert journals.any?
    assert journals.all? {|journal| journal.journalized.is_a?(Issue) && journal.project.id == 1}
  end
end
