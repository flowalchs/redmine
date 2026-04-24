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

require_relative '../test_helper'

class JournalObserverTest < ActiveSupport::TestCase
  def setup
    User.current = nil
    ActionMailer::Base.deliveries.clear
  end

  # context: issue_updated notified_events
  def test_create_should_send_email_notification_with_issue_updated
    issue = Issue.first
    user = User.first
    journal = issue.init_journal(user, "some notes")

    with_settings :notified_events => %w(issue_updated) do
      assert journal.save
    end
    assert_equal 2, ActionMailer::Base.deliveries.size
  end

  def test_create_should_not_send_email_notification_with_notify_set_to_false
    issue = Issue.first
    user = User.first
    journal = issue.init_journal(user, "some notes")
    journal.notify = false

    with_settings :notified_events => %w(issue_updated) do
      assert journal.save
    end
    assert_equal 0, ActionMailer::Base.deliveries.size
  end

  def test_create_should_not_send_email_notification_without_issue_updated
    issue = Issue.first
    user = User.first
    journal = issue.init_journal(user, "some notes")

    with_settings :notified_events => [] do
      assert journal.save
    end
    assert_equal 0, ActionMailer::Base.deliveries.size
  end

  def test_create_should_send_email_notification_with_issue_note_added
    issue = Issue.first
    user = User.first
    journal = issue.init_journal(user)
    journal.notes = 'This update has a note'

    with_settings :notified_events => %w(issue_note_added) do
      assert journal.save
    end
    assert_equal 2, ActionMailer::Base.deliveries.size
  end

  def test_create_should_not_send_email_notification_without_issue_note_added
    issue = Issue.first
    user = User.first
    journal = issue.init_journal(user)
    journal.notes = 'This update has a note'

    with_settings :notified_events => [] do
      assert journal.save
    end
    assert_equal 0, ActionMailer::Base.deliveries.size
  end

  def test_create_should_send_email_notification_with_issue_attr_updated_details_status
    issue = Issue.first
    user = User.first
    issue.init_journal(user)
    issue.status = IssueStatus.last

    with_settings(:notified_events => [], :notified_event_issue_attr_updated_details => %w(status_id)) do
      assert issue.save
    end
    assert_equal 2, ActionMailer::Base.deliveries.size
  end

  def test_create_should_send_email_notification_with_issue_attr_updated
    issue = Issue.first
    user = User.first
    issue.init_journal(user)
    issue.status = IssueStatus.last

    with_settings(:notified_events => %w(issue_attr_updated), :notified_event_issue_attr_updated_details => []) do
      assert issue.save
    end
    assert_equal 2, ActionMailer::Base.deliveries.size
  end

  def test_create_should_not_send_email_notification_without_issue_attr_updated_details_status
    issue = Issue.first
    user = User.first
    issue.init_journal(user)
    issue.status = IssueStatus.last

    with_settings(:notified_events => [], :notified_event_issue_attr_updated_details => []) do
      assert issue.save
    end
    assert_equal 0, ActionMailer::Base.deliveries.size
  end

  def test_create_without_status_update_should_not_send_email_notification_with_issue_attr_updated_details_status
    issue = Issue.first
    user = User.first
    issue.init_journal(user)
    issue.subject = "No status update"

    with_settings(:notified_events => [], :notified_event_issue_attr_updated_details => %w(status_id)) do
      assert issue.save
    end
    assert_equal 0, ActionMailer::Base.deliveries.size
  end

  def test_create_should_send_email_notification_with_issue_attr_updated_details_assignee
    issue = Issue.generate!(:assigned_to_id => 2)
    ActionMailer::Base.deliveries.clear
    user = User.first
    issue.init_journal(user)
    issue.assigned_to = User.find(3)

    with_settings(:notified_events => [], :notified_event_issue_attr_updated_details => %w(assigned_to_id)) do
      assert issue.save
    end
    assert_equal 2, ActionMailer::Base.deliveries.size
  end

  def test_create_should_send_email_notification_with_issue_attr_updated_assignee
    issue = Issue.generate!(:assigned_to_id => 2)
    ActionMailer::Base.deliveries.clear
    user = User.first
    issue.init_journal(user)
    issue.assigned_to = User.find(3)

    with_settings(:notified_events => %w(issue_attr_updated), :notified_event_issue_attr_updated_details => []) do
      assert issue.save
    end
    assert_equal 2, ActionMailer::Base.deliveries.size
  end

  def test_create_should_not_send_email_notification_without_issue_attr_updated_details_assignee
    issue = Issue.generate!(:assigned_to_id => 2)
    ActionMailer::Base.deliveries.clear
    user = User.first
    issue.init_journal(user)
    issue.assigned_to = User.find(3)

    with_settings(:notified_events => [], :notified_event_issue_attr_updated_details => []) do
      assert issue.save
    end
    assert_equal 0, ActionMailer::Base.deliveries.size
  end

  def test_create_should_send_email_notification_with_issue_attr_updated_details_priority
    issue = Issue.first
    user = User.first
    issue.init_journal(user)
    issue.priority = IssuePriority.last

    with_settings(:notified_events => [], :notified_event_issue_attr_updated_details => %w(priority_id)) do
      assert issue.save
    end
    assert_equal 2, ActionMailer::Base.deliveries.size
  end

  def test_create_should_send_email_notification_with_issue_attr_updated_priority
    issue = Issue.first
    user = User.first
    issue.init_journal(user)
    issue.priority = IssuePriority.last

    with_settings(:notified_events => %w(issue_attr_updated), :notified_event_issue_attr_updated_details => []) do
      assert issue.save
    end
    assert_equal 2, ActionMailer::Base.deliveries.size
  end

  def test_create_should_not_send_email_notification_without_issue_attr_updated_details_priority
    issue = Issue.first
    user = User.first
    issue.init_journal(user)
    issue.priority = IssuePriority.last

    with_settings(:notified_events => [], :notified_event_issue_attr_updated_details => []) do
      assert issue.save
    end
    assert_equal 0, ActionMailer::Base.deliveries.size
  end

  def test_create_should_send_email_notification_with_issue_attr_updated_details_fixed_version
    with_settings(:notified_events => [], :notified_event_issue_attr_updated_details => %w(fixed_version_id)) do
      user = User.find_by_login('jsmith')
      issue = issues(:issues_001)
      issue.init_journal(user)
      issue.fixed_version = versions(:versions_003)

      assert issue.save
      assert_equal 2, ActionMailer::Base.deliveries.size
    end
  end

  def test_create_should_send_email_notification_with_issue_attr_updated_fixed_version
    with_settings(:notified_events  => %w(issue_attr_updated), :notified_event_issue_attr_updated_details => []) do
      user = User.find_by_login('jsmith')
      issue = issues(:issues_001)
      issue.init_journal(user)
      issue.fixed_version = versions(:versions_003)

      assert issue.save
      assert_equal 2, ActionMailer::Base.deliveries.size
    end
  end

  def test_create_should_not_send_email_notification_without_issue_attr_updated_details_fixed_version
    with_settings(:notified_events => [], :notified_event_issue_attr_updated_details => []) do
      user = User.find_by_login('jsmith')
      issue = issues(:issues_001)
      issue.init_journal(user)
      issue.fixed_version = versions(:versions_003)

      assert issue.save
      assert_equal 0, ActionMailer::Base.deliveries.size
    end
  end

  def test_create_should_send_email_notification_with_issue_attachment_added
    set_tmp_attachments_directory
    with_settings :notified_events => %w(issue_attachment_added) do
      user = User.find_by_login('jsmith')
      issue = issues(:issues_001)
      issue.init_journal(user)
      issue.save_attachments(
        { 'p0' => {'file' => mock_file_with_options(:original_filename => 'upload')} }
      )

      assert issue.save
      assert_equal 2, ActionMailer::Base.deliveries.size
    end
  end

  def test_create_should_not_send_email_notification_without_issue_attachment_added
    set_tmp_attachments_directory
    with_settings :notified_events => [] do
      user = User.find_by_login('jsmith')
      issue = issues(:issues_001)
      issue.init_journal(user)
      issue.save_attachments(
        { 'p0' => {'file' => mock_file_with_options(:original_filename => 'upload')} }
      )

      assert issue.save
      assert_equal 0, ActionMailer::Base.deliveries.size
    end
  end

  def test_notify_on_issue_relation_updated_with_selected_relation_type
    issue = Issue.first
    other_issue = Issue.generate!(:assigned_to_id => 2)
    user = User.first
    issue.init_journal(user)

    with_settings(notified_events: [], notified_event_issue_relation_updated_details: %w(relates)) do
      IssueRelation.create!(
        issue_from: issue,
        issue_to: other_issue,
        relation_type: 'relates'
      )
    end
    assert_equal 2, ActionMailer::Base.deliveries.size
  end

  def test_notify_on_issue_relation_updated_when_event_enabled
    issue = Issue.first
    other_issue = Issue.generate!(:assigned_to_id => 2)
    user = User.first
    issue.init_journal(user)

    with_settings(:notified_events => %w(issue_relation_updated), :notified_event_issue_attr_updated_details => []) do
      IssueRelation.create!(
        issue_from: issue,
        issue_to: other_issue,
        relation_type: 'relates'
      )
    end
    assert_equal 2, ActionMailer::Base.deliveries.size
  end

  def test_do_not_notify_on_issue_relation_updated_with_unselected_relation_type
    issue = Issue.first
    other_issue = Issue.generate!(:assigned_to_id => 2)
    user = User.first
    issue.init_journal(user)

    with_settings(notified_events: [], notified_event_issue_relation_updated_details: %w(blocks follows)) do
      IssueRelation.create!(
        issue_from: issue,
        issue_to: other_issue,
        relation_type: 'relates'
      )
    end
    assert_equal 0, ActionMailer::Base.deliveries.size
  end

  def test_notify_on_issue_relation_updated_with_selected_relation_type_follows
    issue = Issue.first
    other_issue = Issue.generate!(:assigned_to_id => 2)
    user = User.first
    issue.init_journal(user)

    with_settings(notified_events: [], notified_event_issue_relation_updated_details: %w(blocks follows)) do
      IssueRelation.create!(
        issue_from: issue,
        issue_to: other_issue,
        relation_type: 'follows'
      )
    end
    assert_equal 2, ActionMailer::Base.deliveries.size
  end

  def test_notify_on_issue_custom_field_updated_with_selected_custom_field
    issue = Issue.first
    user  = User.first
    cf = IssueCustomField.find_by!(field_format: 'string')
    issue.init_journal(user)
    issue.custom_field_values = { cf.id => 'New value' }

    with_settings(:notified_events => [], :notified_event_issue_cf_updated_details => [cf.id.to_s]) do
      assert issue.save
    end
    assert_equal 2, ActionMailer::Base.deliveries.size
  end

  def test_notify_on_issue_custom_field_updated_when_event_enabled
    issue = Issue.first
    user  = User.first
    cf = IssueCustomField.find_by!(field_format: 'string')
    issue.init_journal(user)
    issue.custom_field_values = { cf.id => 'Changed value' }

    with_settings(notified_events: %w(issue_cf_updated), notified_event_issue_cf_updated_details: []) do
      assert issue.save
    end
    assert_equal 2, ActionMailer::Base.deliveries.size
  end

  def test_do_not_notify_on_issue_custom_field_updated_with_unselected_custom_field
    issue = Issue.first
    user  = User.first
    cf1 = IssueCustomField.find_by!(field_format: 'string')
    cf2 = IssueCustomField.create!(
      name: 'Second CF',
      field_format: 'string',
      is_for_all: true,
      trackers: Tracker.all
    )
    issue.init_journal(user)
    issue.custom_field_values = { cf2.id => 'Ignored value' }

    with_settings(notified_events: [], notified_event_issue_cf_updated_details: [cf1.id.to_s]) do
      assert issue.save
    end
    assert_equal 0, ActionMailer::Base.deliveries.size
  end

  def test_notify_on_issue_custom_field_updated_with_other_selected_custom_field
    issue = Issue.first
    user  = User.first
    cf1 = IssueCustomField.find_by!(field_format: 'string')
    cf2 = IssueCustomField.create!(
      name: 'Second CF',
      field_format: 'string',
      is_for_all: true,
      trackers: Tracker.all
    )
    issue.init_journal(user)
    issue.custom_field_values = { cf2.id => 'Relevant value' }

    with_settings(notified_events: [], notified_event_issue_cf_updated_details: [cf2.id.to_s]) do
      assert issue.save
    end
    assert_equal 2, ActionMailer::Base.deliveries.size
  end

  def test_notify_on_issue_custom_field_updated_with_multiple_selected_custom_fields
    issue = Issue.first
    user  = User.first
    cf1 = IssueCustomField.find_by!(field_format: 'string')
    cf2 = IssueCustomField.create!(
      name: 'Second CF',
      field_format: 'string',
      is_for_all: true,
      trackers: Tracker.all
    )
    issue.init_journal(user)
    issue.custom_field_values = { cf2.id => 'Matching value' }

    with_settings(notified_events: [], notified_event_issue_cf_updated_details: [cf1.id.to_s, cf2.id.to_s]) do
      assert issue.save
    end
    assert_equal 2, ActionMailer::Base.deliveries.size
  end
end
