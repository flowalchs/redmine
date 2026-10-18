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
    # Makes a model journalized, i.e. its changes and notes are recorded
    # as Journal records.
    #
    #   acts_as_journalized(
    #     :activity_type => 'issues',
    #     :attributes => %w(subject description),
    #     :permissions => {
    #       :edit_notes => :edit_issue_notes,
    #       :edit_own_notes => :edit_own_issue_notes,
    #       :add_watchers => :add_issue_watchers
    #     }
    #   )
    #
    # Options:
    # * :activity_type - registers the journals of the model as activity
    #   provider of the given event type (optional)
    # * :attributes - names of the attributes to journalize, unless the model
    #   defines #journalized_attribute_names
    # * :permissions - permissions used by the default implementations, see
    #   DEFAULT_PERMISSIONS. A nil permission is never granted.
    #
    # The defaults assume that the model has a visible scope and a visible?
    # method, and optionally a project association. Every journal_* method
    # can be overridden by the model for specific behavior.
    module Journalized
      DEFAULT_PERMISSIONS = {
        :edit_notes => nil,
        :edit_own_notes => nil,
        :view_private_notes => :view_private_notes,
        :set_notes_private => :set_notes_private,
        :add_watchers => nil
      }.freeze

      @journalized_type_names = []

      class << self
        # Registers a journalized type by its name, so that journals of this
        # type are taken into account even if the class is not loaded yet
        def register(class_name)
          name = class_name.to_s
          @journalized_type_names << name unless @journalized_type_names.include?(name)
        end

        def unregister(class_name)
          @journalized_type_names.delete(class_name.to_s)
        end

        def journalized_type_names
          @journalized_type_names.dup
        end

        # Returns the classes of the registered journalized types
        def journalized_classes
          @journalized_type_names.filter_map do |name|
            klass = name.safe_constantize
            klass if klass.respond_to?(:journalized_options)
          end
        end
      end

      def self.included(base)
        base.extend ClassMethods
      end

      module ClassMethods
        def acts_as_journalized(options = {})
          options.assert_valid_keys(:activity_type, :attributes, :permissions)
          permissions = options[:permissions] || {}
          permissions.assert_valid_keys(*DEFAULT_PERMISSIONS.keys)

          class_attribute :journalized_options, :instance_writer => false
          self.journalized_options = {
            :activity_type => options[:activity_type]&.to_s,
            :attributes => Array(options[:attributes]).map(&:to_s),
            :permissions => DEFAULT_PERMISSIONS.merge(permissions)
          }

          has_many :journals, :as => :journalized, :dependent => :destroy, :inverse_of => :journalized

          extend SingletonMethods
          include InstanceMethods

          Redmine::Acts::Journalized.register(polymorphic_name)
          Journal.register_activity_provider(self) if journalized_options[:activity_type]
        end
      end

      module SingletonMethods
        # Returns a SQL condition on the tables joined by journal_joins that
        # restricts journals to the ones visible to user, including private
        # notes, or nil if the model does not provide one.
        #
        # Journal.visible uses it when only the journals of this type are
        # queried. Joins usually perform better than the EXISTS subquery of
        # journal_visible_condition, which is used otherwise.
        def journal_visible_join_condition(user=User.current, options={})
          nil
        end

        # Returns a SQL condition that restricts journals to the journals
        # of this type that are visible to user, including private notes
        def journal_visible_condition(user=User.current, options={})
          return '1=0' unless respond_to?(:visible)

          journals = Journal.table_name
          records = visible(user, options).
            where("#{table_name}.#{primary_key} = #{journals}.journalized_id").
            where(journal_private_notes_condition(user, options))
          "#{journals}.journalized_type = #{connection.quote(polymorphic_name)}" \
            " AND EXISTS (#{records.select('1').to_sql})"
        end

        # Returns a SQL condition to filter out journals with private notes
        # that are not visible to user
        def journal_private_notes_condition(user=User.current, options={})
          journals = Journal.table_name
          permission = journalized_options[:permissions][:view_private_notes]
          allowed =
            if user.admin?
              '1=1'
            elsif permission && (reflection = journal_project_reflection)
              project_condition =
                Project.allowed_to_condition(user, permission, options.merge(:skip_pre_condition => true))
              "#{table_name}.#{reflection.foreign_key} IN" \
                " (SELECT #{Project.table_name}.id FROM #{Project.table_name} WHERE #{project_condition})"
            else
              '1=0'
            end
          sanitize_sql_for_conditions(
            ["(#{journals}.private_notes = ? OR #{journals}.user_id = ? OR (#{allowed}))", false, user.id]
          )
        end

        # Returns the SQL joins from the journals table to the table of this
        # type and, if any, to the projects table. The journals must also be
        # restricted to this type, see Journal.joins_journalized
        def journal_joins
          journals = Journal.table_name
          joins = ["INNER JOIN #{table_name} ON #{table_name}.#{primary_key} = #{journals}.journalized_id"]
          if (reflection = journal_project_reflection)
            joins << "INNER JOIN #{Project.table_name} ON #{Project.table_name}.id = #{table_name}.#{reflection.foreign_key}"
          end
          joins
        end

        # Returns the scope of the activity events. The given scope contains
        # the journals of this type only, joined with journal_joins
        def journal_activity_scope(scope)
          scope
        end

        def journal_activity_preload
          journal_project_reflection ? [{:journalized => :project}, :user] : [:user]
        end

        def journal_project_reflection
          reflection = reflect_on_association(:project)
          reflection if reflection&.belongs_to?
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
          {:controller => self.class.model_name.plural, :action => 'show', :id => id, :anchor => "change-#{journal.id}"}
        end

        # Called after a journal is created, if notifications are enabled
        def journal_notify(journal)
        end

        # Called before a journal is created
        def journal_process_watchers(journal)
        end

        # Attributes whose changes are journalized
        def journalized_attribute_names
          journalized_options[:attributes]
        end

        def journal_notified_users
          respond_to?(:notified_users) ? notified_users : []
        end

        def journal_notified_watchers
          respond_to?(:notified_watchers) ? notified_watchers : []
        end

        def journal_visible?(user=User.current)
          respond_to?(:visible?) && visible?(user)
        end

        def journal_project
          respond_to?(:project) ? project : nil
        end

        def journal_editable_by?(journal, user)
          return false unless user&.logged?

          journal_allowed_to?(user, :edit_notes) ||
            (journal.user == user && journal_allowed_to?(user, :edit_own_notes))
        end

        def journal_user_can_view_private_notes?(user)
          journal_allowed_to?(user, :view_private_notes)
        end

        def journal_private_notes_allowed?(user)
          journal_allowed_to?(user, :set_notes_private)
        end

        def journal_valid_watcher?(user)
          user.active? &&
            journal_allowed_to?(user, :add_watchers) &&
            respond_to?(:valid_watcher?) && valid_watcher?(user) &&
            !watched_by?(user)
        end

        # Returns true if the relation of the given journal detail is visible to user
        def journal_relation_visible?(detail, user)
          false
        end

        # Returns the new status if the journal contains a status change, otherwise nil
        def journal_new_status(journal)
          nil
        end

        private

        # Checks the permission configured for key (see DEFAULT_PERMISSIONS)
        # on the journalized project, or globally if there is no project
        def journal_allowed_to?(user, key)
          permission = journalized_options[:permissions][key]
          return false if permission.nil? || user.nil?

          if (project = journal_project)
            user.allowed_to?(permission, project)
          else
            user.allowed_to?(permission, nil, :global => true)
          end
        end
      end
    end
  end
end
