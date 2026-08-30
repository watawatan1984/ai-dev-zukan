# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_30_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

  create_table "admin_audit_logs", force: :cascade do |t|
    t.string "action", null: false
    t.bigint "actor_id", null: false
    t.bigint "auditable_id", null: false
    t.string "auditable_type", null: false
    t.jsonb "changeset", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "request_id"
    t.datetime "updated_at", null: false
    t.index ["action", "created_at"], name: "index_admin_audit_logs_on_action_and_created_at"
    t.index ["actor_id"], name: "index_admin_audit_logs_on_actor_id"
    t.index ["auditable_type", "auditable_id"], name: "index_admin_audit_logs_on_auditable"
  end

  create_table "bookmarks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "resource_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["resource_id"], name: "index_bookmarks_on_resource_id"
    t.index ["user_id", "resource_id"], name: "index_bookmarks_on_user_id_and_resource_id", unique: true
    t.index ["user_id"], name: "index_bookmarks_on_user_id"
  end

  create_table "categories", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_categories_on_slug", unique: true
  end

  create_table "hidden_resources", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "resource_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["resource_id"], name: "index_hidden_resources_on_resource_id"
    t.index ["user_id", "resource_id"], name: "index_hidden_resources_on_user_id_and_resource_id", unique: true
    t.index ["user_id"], name: "index_hidden_resources_on_user_id"
  end

  create_table "import_runs", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "created_count", default: 0, null: false
    t.text "error_message"
    t.integer "fetched_count", default: 0, null: false
    t.string "source_name", null: false
    t.datetime "started_at", null: false
    t.integer "status", default: 0, null: false
    t.integer "unchanged_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["source_name", "started_at"], name: "index_import_runs_on_source_name_and_started_at"
    t.index ["status", "started_at"], name: "index_import_runs_on_status_and_started_at"
  end

  create_table "oauth_identities", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.string "provider", null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["provider", "uid"], name: "index_oauth_identities_on_provider_and_uid", unique: true
    t.index ["user_id", "provider"], name: "index_oauth_identities_on_user_id_and_provider", unique: true
    t.index ["user_id"], name: "index_oauth_identities_on_user_id"
  end

  create_table "resource_revisions", force: :cascade do |t|
    t.string "ai_model"
    t.string "ai_provider"
    t.text "ai_summary"
    t.string "author_name"
    t.jsonb "capabilities", default: [], null: false
    t.datetime "created_at", null: false
    t.jsonb "key_points", default: [], null: false
    t.integer "origin", null: false
    t.string "prompt_version"
    t.text "rejection_reason"
    t.bigint "resource_id", null: false
    t.integer "review_status", default: 0, null: false
    t.datetime "reviewed_at"
    t.bigint "reviewed_by_id"
    t.text "source_excerpt"
    t.string "source_fingerprint", null: false
    t.string "suggested_category_slug"
    t.jsonb "suggested_tag_slugs", default: [], null: false
    t.string "summary_basis"
    t.datetime "summary_generated_at"
    t.string "summary_input_sha256"
    t.integer "summary_status", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["resource_id", "source_fingerprint"], name: "index_resource_revisions_on_resource_and_fingerprint", unique: true
    t.index ["resource_id"], name: "index_resource_revisions_on_resource_id"
    t.index ["review_status", "created_at"], name: "index_resource_revisions_on_review_status_and_created_at"
    t.index ["reviewed_by_id"], name: "index_resource_revisions_on_reviewed_by_id"
  end

  create_table "resource_tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "origin", default: 0, null: false
    t.bigint "resource_id", null: false
    t.bigint "tag_id", null: false
    t.datetime "updated_at", null: false
    t.index ["resource_id", "tag_id"], name: "index_resource_tags_on_resource_id_and_tag_id", unique: true
    t.index ["resource_id"], name: "index_resource_tags_on_resource_id"
    t.index ["tag_id"], name: "index_resource_tags_on_tag_id"
  end

  create_table "resources", force: :cascade do |t|
    t.datetime "archived_at"
    t.text "canonical_url", null: false
    t.bigint "category_id"
    t.datetime "created_at", null: false
    t.bigint "current_revision_id"
    t.string "external_uid"
    t.integer "kind", null: false
    t.datetime "last_synced_at"
    t.text "normalized_canonical_url", null: false
    t.bigint "popularity_raw", default: 0, null: false
    t.decimal "popularity_score", precision: 6, scale: 5, default: "0.0", null: false
    t.integer "publication_status", default: 0, null: false
    t.datetime "published_at"
    t.text "search_text", default: "", null: false
    t.string "slug", null: false
    t.integer "source_provider", null: false
    t.datetime "source_published_at"
    t.datetime "source_updated_at"
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_resources_on_category_id"
    t.index ["current_revision_id"], name: "index_resources_on_current_revision_id", unique: true
    t.index ["kind", "normalized_canonical_url"], name: "index_resources_on_kind_and_normalized_url", unique: true
    t.index ["kind", "source_provider", "external_uid"], name: "index_resources_on_external_identity", unique: true, where: "(external_uid IS NOT NULL)"
    t.index ["publication_status", "kind", "published_at"], name: "idx_on_publication_status_kind_published_at_a8fb4e6e24"
    t.index ["search_text"], name: "index_resources_on_search_text", opclass: :gin_trgm_ops, using: :gin
    t.index ["slug"], name: "index_resources_on_slug", unique: true
  end

  create_table "scheduled_executions", force: :cascade do |t|
    t.string "active_job_id"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "scheduled_for", null: false
    t.integer "status", default: 0, null: false
    t.string "task_name", null: false
    t.datetime "updated_at", null: false
    t.index ["status", "scheduled_for"], name: "index_scheduled_executions_on_status_and_scheduled_for"
    t.index ["task_name", "scheduled_for"], name: "index_scheduled_executions_on_task_name_and_scheduled_for", unique: true
  end

  create_table "solid_queue_batch_executions", force: :cascade do |t|
    t.bigint "batch_id", null: false
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.index ["batch_id"], name: "index_solid_queue_batch_executions_on_batch_id"
    t.index ["job_id"], name: "index_solid_queue_batch_executions_on_job_id", unique: true
  end

  create_table "solid_queue_batches", force: :cascade do |t|
    t.string "active_job_batch_id"
    t.integer "completed_jobs", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.datetime "enqueued_at"
    t.datetime "failed_at"
    t.integer "failed_jobs", default: 0, null: false
    t.datetime "finished_at"
    t.text "metadata"
    t.text "on_failure"
    t.text "on_finish"
    t.text "on_success"
    t.integer "total_jobs", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_batch_id"], name: "index_solid_queue_batches_on_active_job_batch_id", unique: true
    t.index ["finished_at"], name: "index_solid_queue_batches_on_finished_at"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.bigint "batch_id"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["batch_id"], name: "index_solid_queue_jobs_on_batch_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "normalized_name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["normalized_name"], name: "index_tags_on_normalized_name", unique: true
    t.index ["slug"], name: "index_tags_on_slug", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.integer "appearance", default: 0, null: false
    t.datetime "confirmation_sent_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.integer "failed_attempts", default: 0, null: false
    t.datetime "locked_at"
    t.string "name", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "role", default: 0, null: false
    t.string "unconfirmed_email"
    t.string "unlock_token"
    t.datetime "updated_at", null: false
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["role"], name: "index_users_on_role"
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
  end

  add_foreign_key "admin_audit_logs", "users", column: "actor_id"
  add_foreign_key "bookmarks", "resources"
  add_foreign_key "bookmarks", "users"
  add_foreign_key "hidden_resources", "resources"
  add_foreign_key "hidden_resources", "users"
  add_foreign_key "oauth_identities", "users"
  add_foreign_key "resource_revisions", "resources"
  add_foreign_key "resource_revisions", "users", column: "reviewed_by_id"
  add_foreign_key "resource_tags", "resources"
  add_foreign_key "resource_tags", "tags"
  add_foreign_key "resources", "categories"
  add_foreign_key "resources", "resource_revisions", column: "current_revision_id"
  add_foreign_key "solid_queue_batch_executions", "solid_queue_batches", column: "batch_id", on_delete: :cascade
  add_foreign_key "solid_queue_batch_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
end
