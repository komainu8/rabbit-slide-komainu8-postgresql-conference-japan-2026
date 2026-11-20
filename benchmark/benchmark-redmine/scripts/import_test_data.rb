# frozen_string_literal: true

require "csv"
require "set"

PROJECT_NAME = "架空の物流会社チケット検索"
PROJECT_IDENTIFIER = "search-methods-benchmark"
TEST_ISSUE_PREFIX = "BENCH"
MAX_SUBJECT_LENGTH = 255

csv_path = ENV.fetch("TEST_DATA_CSV", "/opt/redmine-import/data/documents.csv")
raise "テストデータCSVが見つかりません: #{csv_path}" unless File.file?(csv_path)

rows = CSV.read(csv_path, headers: true, encoding: "bom|utf-8", liberal_parsing: true)
required_headers = %w[id subject description]
missing_headers = required_headers - Array(rows.headers).map(&:to_s)
raise "CSVに必要な列がありません: #{missing_headers.join(', ')}" unless missing_headers.empty?

documents = []
seen_ids = {}
rows.each_with_index do |row, index|
  source_id = row["id"].to_s.strip
  subject = row["subject"].to_s.strip
  description = row["description"].to_s.strip
  next if source_id.empty? && subject.empty? && description.empty?
  raise "CSV #{index + 2}行目: idは整数で指定してください: #{source_id.inspect}" unless source_id.match?(/\A\d+\z/)
  id = Integer(source_id, 10)
  raise "CSV #{index + 2}行目: idは1以上で指定してください" unless id.positive?
  raise "CSV #{index + 2}行目: subjectが空です" if subject.empty?
  raise "CSV #{index + 2}行目: descriptionが空です" if description.empty?
  raise "CSV内でid=#{id}が重複しています" if seen_ids.key?(id)
  seen_ids[id] = true
  documents << {id: id, subject: subject, description: description}
end
raise "CSVに登録対象のデータがありません" if documents.empty?

project = Project.find_by(identifier: PROJECT_IDENTIFIER)
project ||= Project.new(
  name: PROJECT_NAME,
  identifier: PROJECT_IDENTIFIER,
  description: "架空の物流会社のチケットを題材にした検索方式比較用データ",
  is_public: true
)
project.enabled_module_names = (Array(project.enabled_module_names) + ["issue_tracking"]).uniq
project.save!

if project.trackers.empty?
  project.trackers = Tracker.sorted.to_a
  project.save!
end
tracker = project.trackers.to_a.sort_by { |item| item.position || 0 }.first
unless tracker
  raise "Redmineにトラッカーがありません。先に redmine:load_default_data を実行してください。"
end
status = tracker.default_status || IssueStatus.default || IssueStatus.first
raise "利用可能なチケットステータスがありません" unless status
priority = IssuePriority.default_or_middle || IssuePriority.first
raise "利用可能なチケット優先度がありません" unless priority
author = User.active.where(admin: true).first
raise "有効な管理者ユーザーが見つかりません" unless author
User.current = author

existing_by_id = {}
project.issues.where("subject LIKE ?", "[#{TEST_ISSUE_PREFIX}-%").find_each do |issue|
  match = issue.subject.match(/\A\[#{TEST_ISSUE_PREFIX}-(\d+)\]/)
  next unless match
  id = match[1].to_i
  raise "BENCH-#{id}のチケットが複数あります" if existing_by_id.key?(id)
  existing_by_id[id] = issue
end

created = updated = unchanged = deleted = 0
incoming_ids = documents.map { |document| document.fetch(:id) }.to_set
Issue.transaction do
  documents.each do |document|
    id = document.fetch(:id)
    marker = format("[%s-%04d]", TEST_ISSUE_PREFIX, id)
    title = document.fetch(:subject)
    subject = "#{marker} #{title}"
    subject = subject.slice(0, MAX_SUBJECT_LENGTH) if subject.length > MAX_SUBJECT_LENGTH
    description = document.fetch(:description)
    issue = existing_by_id[id]
    if issue
      if issue.subject == subject && issue.description == description
        unchanged += 1
        next
      end
      issue.subject = subject
      issue.description = description
      issue.save!
      updated += 1
      puts "Updated ##{issue.id} from dataset id=#{id}"
    else
      issue = Issue.new(
        project: project, tracker: tracker, status: status,
        priority: priority, author: author, subject: subject,
        description: description, is_private: false
      )
      issue.save!
      created += 1
      puts "Created ##{issue.id} from dataset id=#{id}"
    end
  end

  # Remove only issues managed by this importer (the [BENCH-NNNN] prefix)
  # when their dataset IDs are no longer present. This clears the old 1..40
  # sample set without touching ordinary project issues.
  existing_by_id.each do |id, issue|
    next if incoming_ids.include?(id)

    issue.destroy!
    deleted += 1
    puts "Deleted stale test issue ##{issue.id} (dataset id=#{id})"
  end
end

puts
puts "Import completed."
puts "Project: #{project.name} (#{project.identifier})"
puts "Dataset rows: #{documents.length}"
puts "Created: #{created}"
puts "Updated: #{updated}"
puts "Unchanged: #{unchanged}"
puts "Deleted stale managed test issues: #{deleted}"
puts "Category column is metadata only; it is not copied into the issue text."
