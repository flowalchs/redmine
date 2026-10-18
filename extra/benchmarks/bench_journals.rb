# frozen_string_literal: true

# Benchmark of the journal queries affected by the Journal/Issue decoupling (#44274).
#
# Runs with the same data on both variants, eg.:
#
#   git checkout 7.0-stable         && bin/rails r extra/benchmarks/bench_journals.rb
#   git checkout journal-decoupling && bin/rails r extra/benchmarks/bench_journals.rb
#   CLEANUP=1 bin/rails r extra/benchmarks/bench_journals.rb
#
# The benchmark data is created on the first run and kept (and analyzed),
# so that both variants run against the same data and statistics.
# Use CLEANUP=1 to remove it. Do not run it on a production database.
#
# Environment variables:
# * PROJECTS (default 20), ISSUES (default 20000), JOURNALS_PER_ISSUE (default 10):
#   size of the data, used when the data is created
# * ITER (default 10): iterations of each benchmark, the median is reported
# * ONLY: comma separated names of the benchmarks to run (default all)
# * EXPLAIN=1: prints the query plans of the visible journals query

require 'benchmark'

# Do not measure the SQL logging (eg. verbose query logs in development)
ActiveRecord::Base.logger = nil

PREFIX = 'bench-journals'
projects_count = (ENV['PROJECTS'] || '20').to_i
issues_count = (ENV['ISSUES'] || '20000').to_i
journals_per_issue = (ENV['JOURNALS_PER_ISSUE'] || '10').to_i
iterations = (ENV['ITER'] || '10').to_i

def bench_projects
  Project.where("identifier LIKE ?", "#{PREFIX}-%").order(:id)
end

def bench_users
  User.where("login LIKE ?", "#{PREFIX.tr('-', '_')}_%").order(:id)
end

def cleanup
  projects = bench_projects.to_a
  project_ids = projects.map(&:id)
  issue_ids = Issue.where(:project_id => project_ids).pluck(:id)
  ActiveRecord::Base.transaction do
    journal_ids = Journal.where(:journalized_type => 'Issue', :journalized_id => issue_ids).pluck(:id)
    journal_ids.each_slice(10_000) do |ids|
      JournalDetail.where(:journal_id => ids).delete_all
      Journal.where(:id => ids).delete_all
    end
    Issue.where(:id => issue_ids).delete_all
    member_ids = Member.where(:project_id => project_ids).pluck(:id)
    MemberRole.where(:member_id => member_ids).delete_all
    Member.where(:id => member_ids).delete_all
    EnabledModule.where(:project_id => project_ids).delete_all
    Project.connection.execute("DELETE FROM projects_trackers WHERE project_id IN (#{project_ids.join(',')})") if project_ids.any?
    Project.where(:id => project_ids).delete_all
    bench_users.each(&:destroy)
    Role.where("name LIKE ?", "#{PREFIX} %").delete_all
  end
  Project.rebuild_tree! if Project.respond_to?(:rebuild_tree!)
  puts "Benchmark data removed (#{issue_ids.size} issues)."
end

def create_data(projects_count, issues_count, journals_per_issue)
  now = Time.now.utc
  rand = Random.new(44274)
  tracker = Tracker.order(:position).first || raise('No tracker found, load the default data')
  statuses = IssueStatus.order(:position).to_a
  priority = IssuePriority.default || IssuePriority.first || raise('No issue priority found')
  admin = User.where(:admin => true).active.first || raise('No active admin found')

  ActiveRecord::Base.transaction do
    manager = Role.create!(:name => "#{PREFIX} manager", :permissions => [:view_issues, :view_private_notes])
    reporter = Role.create!(:name => "#{PREFIX} reporter", :permissions => [:view_issues])
    member = User.new(:firstname => 'Bench', :lastname => 'Member', :mail => "#{PREFIX}-member@example.net")
    member.login = "#{PREFIX.tr('-', '_')}_member"
    member.save!

    projects = Array.new(projects_count) do |i|
      project = Project.new(:name => "Bench journals #{i}", :identifier => "#{PREFIX}-#{i}",
                            :is_public => i % 4 != 0)
      project.enabled_module_names = ['issue_tracking']
      project.trackers = [tracker]
      project.save!
      # The member is manager of a quarter of the projects, reporter of another quarter
      if i % 4 == 1
        Member.create!(:project => project, :principal => member, :roles => [manager])
      elsif i % 4 == 2
        Member.create!(:project => project, :principal => member, :roles => [reporter])
      end
      project
    end
    print "Projects: #{projects.size}\nInserting issues"

    issues_count.times.each_slice(5_000) do |slice|
      rows = slice.map do |i|
        created_on = now - rand.rand(365 * 24 * 3600)
        {
          :project_id => projects[i % projects.size].id, :tracker_id => tracker.id,
          :subject => "Bench issue #{i}", :author_id => admin.id,
          :status_id => statuses[i % statuses.size].id, :priority_id => priority.id,
          :is_private => (i % 10 == 0), :lft => 1, :rgt => 2, :lock_version => 0, :done_ratio => 0,
          :created_on => created_on, :updated_on => created_on
        }
      end
      Issue.insert_all(rows)
      print '.'
    end
    Issue.where(:project_id => projects.map(&:id)).update_all("root_id = id")
    puts

    print "Inserting journals"
    users = [admin.id, member.id]
    Issue.where(:project_id => projects.map(&:id)).in_batches(:of => 1_000) do |batch|
      journal_rows = []
      batch.pluck(:id, :created_on).each do |issue_id, issue_created_on|
        journals_per_issue.times do |j|
          kind = rand.rand(10)
          journal_rows << {
            :journalized_type => 'Issue', :journalized_id => issue_id, :user_id => users[j % 2],
            :notes => (kind < 6 ? "Note #{j} on issue #{issue_id}" : ''),
            :private_notes => (kind == 0),
            :created_on => issue_created_on + ((j + 1) * 3600), :updated_on => issue_created_on + ((j + 1) * 3600)
          }
        end
      end
      Journal.insert_all(journal_rows)
      # :returning is not supported by all databases
      ids = Journal.where(:journalized_type => 'Issue', :journalized_id => batch.select(:id)).order(:id).pluck(:id)
      # A third of the journals without notes is a status change
      detail_rows = ids.each_with_index.filter_map do |id, index|
        next unless index % 3 == 0

        {:journal_id => id, :property => 'attr', :prop_key => 'status_id',
         :old_value => statuses.first.id.to_s, :value => statuses.last.id.to_s}
      end
      JournalDetail.insert_all(detail_rows) if detail_rows.any?
      print '.'
    end
    puts
  end
end

if ENV['CLEANUP']
  cleanup
  exit
end

if bench_projects.empty?
  create_data(projects_count, issues_count, journals_per_issue)
  conn = ActiveRecord::Base.connection
  %w(issues journals journal_details projects members member_roles).each do |table|
    case conn.adapter_name
    when /postgres/i then conn.execute("ANALYZE #{table}")
    when /mysql|trilogy/i then conn.execute("ANALYZE TABLE #{table}")
    end
  end
end

projects = bench_projects.to_a
project_ids = projects.map(&:id)
member = bench_users.first
admin = User.where(:admin => true).active.first
anonymous = User.anonymous
bench_issue_ids = Issue.where(:project_id => project_ids).order(:id).pluck(:id)
bench_journals = Journal.where(:journalized_type => 'Issue', :journalized_id => bench_issue_ids)
latest = bench_journals.maximum(:created_on)
sample_journal_id = bench_journals.where(:private_notes => false).order(:id).offset(bench_journals.count / 2).pick(:id)

variant = `git rev-parse --abbrev-ref HEAD 2>/dev/null`.strip
variant = Journal.respond_to?(:joins_journalized) ? 'journal-decoupling' : 'legacy' if variant.empty?
puts "variant=#{variant} ruby=#{RUBY_VERSION} rails=#{Rails.version} db=#{ActiveRecord::Base.connection.adapter_name} " \
     "projects=#{projects.size} issues=#{bench_issue_ids.size} journals=#{bench_journals.count} iter=#{iterations}"

if ENV['EXPLAIN']
  [admin, member].each do |user|
    puts "\nEXPLAIN Journal.visible(#{user.login}).order(id DESC).limit(25):"
    puts Journal.visible(user).order(:id => :desc).limit(25).explain.inspect
  end
end

benchmarks = {
  'visible_count' => lambda {|user| Journal.visible(user).count},
  'visible_latest_25' => lambda {|user| Journal.visible(user).reorder(:id => :desc).limit(25).ids.sum},
  'visible_find' => lambda {|user| Journal.visible(user).where(:id => sample_journal_id).ids.sum},
  'activity_project' => lambda do |user|
    Redmine::Activity::Fetcher.new(user, :project => projects[1], :with_subprojects => true).
      events(latest - 30.days, latest).size
  end,
  'activity_all_30d' => lambda {|user| Redmine::Activity::Fetcher.new(user).events(latest - 30.days, latest).size},
  'activity_last_by_project' => lambda {|user| Redmine::Activity::Fetcher.new(user).events(nil, nil, :last_by_project => true).size},
  'issue_query_journals' => lambda do |user|
    User.current = user
    IssueQuery.new(:name => '_').journals(:order => "#{Journal.table_name}.created_on DESC", :limit => 25).sum(&:id)
  end,
  'issue_last_notes_25' => lambda do |user|
    issues = Issue.where(:id => bench_issue_ids.last(25)).to_a
    Issue.load_visible_last_notes(issues, user)
    Issue.load_visible_last_updated_by(issues, user)
    issues.sum {|issue| issue.last_notes.to_s.size}
  end
}

puts
puts format('%-26s %-10s %10s %10s %10s %14s', 'benchmark', 'user', 'median_ms', 'min_ms', 'max_ms', 'result')
only = ENV['ONLY'].to_s.split(',').map(&:strip).reject(&:empty?)
benchmarks.slice!(*only) if only.any?
benchmarks.each do |name, block|
  {'admin' => admin, 'member' => member, 'anonymous' => anonymous}.each do |label, user|
    result = block.call(user) # warm up
    times = ApplicationRecord.uncached do
      Array.new(iterations) { Benchmark.realtime { block.call(user) } * 1000 }
    end.sort
    median = times.size.odd? ? times[times.size / 2] : (times[(times.size / 2) - 1] + times[times.size / 2]) / 2
    puts format('%-26s %-10s %10.2f %10.2f %10.2f %14s', name, label, median, times.first, times.last, result)
  end
end
User.current = nil
