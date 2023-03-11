# frozen_string_literal: true

require "active_support/core_ext/string/filters"
require "active_support/log_subscriber"

module ActiveJob
  class LogSubscriber < ActiveSupport::LogSubscriber # :nodoc:
    def enqueue(event)
      job = event.payload[:job]
      ex = event.payload[:exception_object]

      if ex
        error do
          "Failed enqueuing #{job.class.name} to #{queue_name(event)}: #{ex.class} (#{ex.message})"
        end
      elsif event.payload[:aborted]
        info do
          "Failed enqueuing #{job.class.name} to #{queue_name(event)}, a before_enqueue callback halted the enqueuing execution."
        end
      else
        info do
          "Enqueued #{job.class.name} (Job ID: #{job.job_id}) to #{queue_name(event)}" + args_info(job)
        end
      end
    end
    subscribe_log_level :enqueue, :info

    def enqueue_at(event)
      job = event.payload[:job]
      ex = event.payload[:exception_object]

      if ex
        error do
          "Failed enqueuing #{job.class.name} to #{queue_name(event)}: #{ex.class} (#{ex.message})"
        end
      elsif event.payload[:aborted]
        info do
          "Failed enqueuing #{job.class.name} to #{queue_name(event)}, a before_enqueue callback halted the enqueuing execution."
        end
      else
        info do
          "Enqueued #{job.class.name} (Job ID: #{job.job_id}) to #{queue_name(event)} at #{scheduled_at(event)}" + args_info(job)
        end
      end
    end
    subscribe_log_level :enqueue_at, :info

    def perform_start(event)
      info do
        job = event.payload[:job]
        "Performing #{job.class.name} (Job ID: #{job.job_id}) from #{queue_name(event)} enqueued at #{job.enqueued_at}" + args_info(job)
      end
    end
    subscribe_log_level :perform_start, :info

    def perform(event)
      job = event.payload[:job]
      ex = event.payload[:exception_object]
      if ex
        error do
          "Error performing #{job.class.name} (Job ID: #{job.job_id}) from #{queue_name(event)} in #{event.duration.round(2)}ms: #{ex.class} (#{ex.message}):\n" + Array(ex.backtrace).join("\n")
        end
      elsif event.payload[:aborted]
        error do
          "Error performing #{job.class.name} (Job ID: #{job.job_id}) from #{queue_name(event)} in #{event.duration.round(2)}ms: a before_perform callback halted the job execution"
        end
      else
        info do
          "Performed #{job.class.name} (Job ID: #{job.job_id}) from #{queue_name(event)} in #{event.duration.round(2)}ms"
        end
      end
    end
    subscribe_log_level :perform, :info

    def enqueue_retry(event)
      job = event.payload[:job]
      ex = event.payload[:error]
      wait = event.payload[:wait]

      info do
        if ex
          "Retrying #{job.class} (Job ID: #{job.job_id}) after #{job.executions} attempts in #{wait.to_i} seconds, due to a #{ex.class} (#{ex.message})."
        else
          "Retrying #{job.class} (Job ID: #{job.job_id}) after #{job.executions} attempts in #{wait.to_i} seconds."
        end
      end
    end
    subscribe_log_level :enqueue_retry, :info

    def retry_stopped(event)
      job = event.payload[:job]
      ex = event.payload[:error]

      error do
        "Stopped retrying #{job.class} (Job ID: #{job.job_id}) due to a #{ex.class} (#{ex.message}), which reoccurred on #{job.executions} attempts."
      end
    end
    subscribe_log_level :enqueue_retry, :error

    def discard(event)
      job = event.payload[:job]
      ex = event.payload[:error]

      error do
        "Discarded #{job.class} (Job ID: #{job.job_id}) due to a #{ex.class} (#{ex.message})."
      end
    end
    subscribe_log_level :discard, :error

    private
      def queue_name(event)
        event.payload[:adapter].class.name.demodulize.remove("Adapter") + "(#{event.payload[:job].queue_name})"
      end

      def args_info(job)
        if job.class.log_arguments? && job.arguments.any?
          " with arguments: " +
            job.arguments.map { |arg| format(arg).inspect }.join(", ")
        else
          ""
        end
      end

      def format(arg)
        case arg
        when Hash
          arg.transform_values { |value| format(value) }
        when Array
          arg.map { |value| format(value) }
        when GlobalID::Identification
          arg.to_global_id rescue arg
        else
          arg
        end
      end

      def scheduled_at(event)
        Time.at(event.payload[:job].scheduled_at).utc
      end

      def logger
        ActiveJob::Base.logger
      end
  end
end

ActiveJob::LogSubscriber.attach_to :active_job
