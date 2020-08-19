# frozen_string_literal: true

require 'grape'
require 'ruby-prof'
require 'benchmark/ips'

class ScheduleType
  def type_cast(value, mandatory = true, allow_zero = true)
    return_value = if !value.nil?
                     if /([0-9]+):([0-9]+):([0-9]+)/ =~ value.to_s
                       3600 * Regexp.last_match(1).to_i + 60 * Regexp.last_match(2).to_i + Regexp.last_match(3).to_i
                     elsif /([0-9]+):([0-9]+)/ =~ value.to_s
                       3600 * Regexp.last_match(1).to_i + 60 * Regexp.last_match(2).to_i
                     elsif value.to_s.match? "\A[0-9]+\.{0,1}[0-9]*\z"
                       value.to_i
                     elsif value.is_a?(Integer) || value.is_a?(Float)
                       value.to_i
                     else
                       log 'error', level: :error
                       raise ArgumentError, 'Invalid Time value'
                     end
                   elsif mandatory
                     0
                   end

    if return_value&.negative? || (!allow_zero && return_value&.zero?)
      log 'error', level: :error
      raise ArgumentError, 'Invalid Time value'
    end

    return_value
  end
end

class API < Grape::API
  # include Grape::Extensions::Hash::ParamBuilder
  # include Grape::Extensions::Hashie::Mash::ParamBuilder

  prefix :api
  version 'v1', using: :path

  def self.vrp_request_timewindow(this)
    this.optional(:id, types: String)
    this.optional(:start, types: [String, Float, Integer], coerce_with: ->(value) { ScheduleType.new.type_cast(value, false) })
    this.optional(:end, types: [String, Float, Integer], coerce_with: ->(value) { ScheduleType.new.type_cast(value, false) })
    this.optional(:day_index, type: Integer, values: 0..6)
    this.at_least_one_of :start, :end, :day_index
  end

  def self.vrp_request_indice_range(this)
    this.optional(:start, type: Integer)
    this.optional(:end, type: Integer)
  end

  def self.vrp_request_point(this)
    this.requires(:id, type: String, allow_blank: false)
    this.optional(:location, type: Hash, allow_blank: false) do
      requires(:lat, type: Float, allow_blank: false)
      requires(:lon, type: Float, allow_blank: false)
    end
  end

  def self.vrp_request_unit(this)
    this.requires(:id, type: String, allow_blank: false)
    this.optional(:label, type: String)
    this.optional(:counting, type: Boolean)
  end

  def self.vrp_request_activity(this)
    this.optional(:duration, types: [String, Float, Integer], coerce_with: ->(value) { ScheduleType.new.type_cast(value) })
    this.optional(:additional_value, type: Integer)
    this.optional(:setup_duration, types: [String, Float, Integer], coerce_with: ->(value) { ScheduleType.new.type_cast(value) })
    this.optional(:late_multiplier, type: Float)
    this.optional(:timewindow_start_day_shift_number, documentation: { hidden: true }, type: Integer)
    this.requires(:point_id, type: String, allow_blank: false)
    this.optional(:timewindows, type: Array) do
      API.vrp_request_timewindow(self)
    end
  end

  def self.vrp_request_quantity(this)
    this.optional(:id, type: String)
    this.requires(:unit_id, type: String, allow_blank: false)
    this.optional(:value, type: Float)
  end

  def self.vrp_request_capacity(this)
    this.optional(:id, type: String)
    this.requires(:unit_id, type: String, allow_blank: false)
    this.requires(:limit, type: Float, allow_blank: false)
    this.optional(:initial, type: Float)
    this.optional(:overload_multiplier, type: Float)
  end

  def self.vrp_request_vehicle(this)
    this.requires(:id, type: String, allow_blank: false)
    this.optional(:cost_fixed, type: Float)
    this.optional(:cost_distance_multiplier, type: Float)
    this.optional(:cost_time_multiplier, type: Float)

    this.optional :router_dimension, type: String, values: %w[time distance]
    this.optional(:skills, type: Array[Array[String]])

    this.optional(:unavailable_work_day_indices, type: Array[Integer])

    this.optional(:free_approach, type: Boolean)
    this.optional(:free_return, type: Boolean)

    this.optional(:start_point_id, type: String)
    this.optional(:end_point_id, type: String)
    this.optional(:capacities, type: Array) do
      API.vrp_request_capacity(self)
    end

    this.optional(:sequence_timewindows, type: Array) do
      API.vrp_request_timewindow(self)
    end
  end

  def self.vrp_request_service(this)
    this.requires(:id, type: String, allow_blank: false)
    this.optional(:priority, type: Integer, values: 0..8)
    this.optional(:exclusion_cost, type: Integer)

    this.optional(:visits_number, type: Integer, coerce_with: ->(val) { val.to_i.positive? && val.to_i }, default: 1, allow_blank: false)

    this.optional(:unavailable_visit_indices, type: Array[Integer])
    this.optional(:unavailable_visit_day_indices, type: Array[Integer])

    this.optional(:minimum_lapse, type: Float)
    this.optional(:maximum_lapse, type: Float)

    this.optional(:sticky_vehicle_ids, type: Array[String])
    this.optional(:skills, type: Array[String])

    this.optional(:type, type: Symbol)
    this.optional(:activity, type: Hash) do
      API.vrp_request_activity(self)
    end
    this.optional(:quantities, type: Array) do
      API.vrp_request_quantity(self)
    end
  end

  def self.vrp_request_configuration(this)
    this.optional(:preprocessing, type: Hash) do
      API.vrp_request_preprocessing(self)
    end
    this.optional(:resolution, type: Hash) do
      API.vrp_request_resolution(self)
    end
    this.optional(:restitution, type: Hash) do
      API.vrp_request_restitution(self)
    end
    this.optional(:schedule, type: Hash) do
      API.vrp_request_schedule(self)
    end
  end

  def self.vrp_request_partition(this)
    this.requires(:method, type: String, values: %w[hierarchical_tree balanced_kmeans])
    this.optional(:metric, type: Symbol)
    this.optional(:entity, type: Symbol, values: %i[vehicle work_day], coerce_with: ->(value) { value.to_sym })
    this.optional(:threshold, type: Integer)
  end

  def self.vrp_request_preprocessing(this)
    this.optional(:max_split_size, type: Integer)
    this.optional(:partition_method, type: String, documentation: { hidden: true })
    this.optional(:partition_metric, type: Symbol, documentation: { hidden: true })
    this.optional(:kmeans_centroids, type: Array[Integer])
    this.optional(:cluster_threshold, type: Float)
    this.optional(:force_cluster, type: Boolean)
    this.optional(:prefer_short_segment, type: Boolean)
    this.optional(:neighbourhood_size, type: Integer)
    this.optional(:partitions, type: Array) do
      API.vrp_request_partition(self)
    end
    this.optional(:first_solution_strategy, type: Array[String], coerce_with: ->(value) { FirstSolType.new.type_cast(value) })
  end

  def self.vrp_request_resolution(this)
    this.optional(:duration, type: Integer, allow_blank: false)
    this.optional(:iterations, type: Integer, allow_blank: false)
    this.optional(:iterations_without_improvment, type: Integer, allow_blank: false)
    this.optional(:stable_iterations, type: Integer, allow_blank: false)
    this.optional(:stable_coefficient, type: Float, allow_blank: false)
    this.optional(:initial_time_out, type: Integer, allow_blank: false, documentation: { hidden: true })
    this.optional(:minimum_duration, type: Integer, allow_blank: false)
    this.optional(:time_out_multiplier, type: Integer)
    this.optional(:vehicle_limit, type: Integer)
    this.optional(:solver_parameter, type: Integer, documentation: { hidden: true })
    this.optional(:solver, type: Boolean, default: true)
    this.optional(:same_point_day, type: Boolean)
    this.optional(:allow_partial_assignment, type: Boolean, default: true)
    this.optional(:split_number, type: Integer)
    this.optional(:evaluate_only, type: Boolean)
    this.optional(:several_solutions, type: Integer, allow_blank: false, default: 1)
    this.optional(:batch_heuristic, type: Boolean, default: false)
    this.optional(:variation_ratio, type: Integer)
    this.optional(:repetition, type: Integer, documentation: { hidden: true })
    this.at_least_one_of :duration, :iterations, :iterations_without_improvment, :stable_iterations, :stable_coefficient, :initial_time_out, :minimum_duration
    this.mutually_exclusive :initial_time_out, :minimum_duration
  end

  def self.vrp_request_restitution(this)
    this.optional(:geometry, type: Boolean)
    this.optional(:geometry_polyline, type: Boolean)
    this.optional(:intermediate_solutions, type: Boolean)
    this.optional(:csv, type: Boolean)
    this.optional(:allow_empty_result, type: Boolean)
  end

  def self.vrp_request_schedule(this)
    this.optional(:range_indices, type: Hash) do
      API.vrp_request_indice_range(self)
    end
    this.optional(:unavailable_indices, type: Array[Integer])
  end

  params do
    optional(:vrp, type: Hash, documentation: { param_type: 'body' }) do
      optional(:name, type: String)

      optional(:points, type: Array) do
        API.vrp_request_point(self)
      end

      optional(:units, type: Array) do
        API.vrp_request_unit(self)
      end

      requires(:vehicles, type: Array) do
        API.vrp_request_vehicle(self)
      end

      optional(:services, type: Array, allow_blank: false) do
        API.vrp_request_service(self)
      end

      optional(:configuration, type: Hash) do
        API.vrp_request_configuration(self)
      end
    end
  end
  post '/' do
    'hello'
  end
end

options = {
  method: 'POST',
  params: JSON.parse(File.read('benchmark/resource/vrp_example.json'))
}

env = Rack::MockRequest.env_for('/api/v1', options)

result = RubyProf.profile do
  start = Time.now
    API.call env
  puts Time.now - start
end
printer = RubyProf::FlatPrinter.new(result)
File.open('test_prof.out', 'w+') { |f| printer.print(f, {}) }
