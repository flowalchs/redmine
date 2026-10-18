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

module Redmine
  module Acts
    module Journalized
      def self.included(base)
        base.extend ClassMethods
      end

      module ClassMethods
        def acts_as_journalized(options = {})
          class_attribute :journal_activity_type

          has_many :journals, as: :journalized, dependent: :destroy, inverse_of: :journalized

          Journal.register_journalized_type(self)
          self.journal_activity_type = options[:activity_type]
          Journal.register_activity_provider(self) if journal_activity_type.present?

          include InstanceMethods
        end

        # Visibility
        # Returns journalized records visible for the given user.
        # Default implementation simply returns all records.
        def journal_visible_scope(user = User.current, options = {})
          all
        end

        def journal_notes_visibility_scope(scope, user, options = {})
          scope
        end

        def journal_visibility_scope(scope)
          scope
        end

        # scope contains journals of the current journalized class only
        def journal_activity_scope(scope)
          scope
        end

        def journal_activity_preload
          []
        end
      end

      module InstanceMethods
        # Event API
        def journal_event_title(journal)
          "#{self.class.model_name.human} ##{id}"
        end

        def journal_event_type(journal)
          'journal-update'
        end

        def journal_event_url(journal)
          {}
        end

        # Notification API
        def journal_notify(journal)
          # no-op
        end

        # Watcher API
        def journal_process_watchers(journal)
          # no-op
        end

        # Journal detail tracking API
        def journalized_attribute_names
          []
        end

        # Recipient API
        def journal_notified_users
          respond_to?(:notified_users) ? notified_users : []
        end

        def journal_notified_watchers
          respond_to?(:notified_watchers) ? notified_watchers : []
        end

        # Visibility API
        def journal_visible?(user = User.current)
          respond_to?(:visible?) ? visible?(user) : true
        end

        def journal_project
          respond_to?(:project) ? project : nil
        end

        def journal_editable_by?(journal, user)
          false
        end

        def journal_relation_visible?(detail, user)
          true
        end

        def journal_user_can_view_private_notes?(user)
          true
        end

        def journal_private_notes_allowed?(user)
          false
        end

        def journal_valid_watcher?(user)
          false
        end

        def journal_new_status(journal)
          nil
        end
      end
    end
  end
end
