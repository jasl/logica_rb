# frozen_string_literal: true

require "set"

module LogicaRb
  module Common
    module ConcertinaLib
      class ConcertinaQueryEngine
        attr_reader :final_result, :completion_time

        def initialize(final_predicates, sql_runner, print_running_predicate: true)
          @final_predicates = final_predicates.to_set
          @final_result = {}
          @sql_runner = sql_runner
          @print_running_predicate = print_running_predicate
          @completion_time = {}
        end

        def run(action)
          return unless action["launcher"] == "query"

          predicate = action["predicate"]
          start = Time.now
          result = @sql_runner.call(action["sql"], action["engine"], @final_predicates.include?(predicate))
          elapsed = ((Time.now - start) * 1000).to_i
          @completion_time[predicate] = elapsed
          if @final_predicates.include?(predicate)
            @final_result[predicate] = result
          end
        end
      end

      class Concertina
        def initialize(config, engine, display_mode: "silent", iterations: {})
          @config = config
          @engine = engine
          @display_mode = display_mode
          @iterations = iterations || {}
          @action = @config.each_with_object({}) { |a, h| h[a["name"]] = a }
          @all_actions = @action.keys.to_set
          @complete_actions = Set.new
          @running_actions = Set.new
          @action_stopped = Set.new
          @action_requires = {}
          @action_iteration = {}
          @iteration_repetitions = {}
          @action_iterations_complete = {}
          @iteration_actions = {}
          @iteration_stop_signal = {}
          @half_iteration_actions = {}
          @action_half_iteration = {}
          @wrench_in_gears = Set.new
          @actions_to_run = []
          understand_iterations
          @actions_to_run = sort_actions
        end

        def run
          run_one_action while @actions_to_run.any?
        end

        private

        def understand_iterations
          @iterations.each do |iteration, info|
            info = info.transform_keys(&:to_s)
            predicates = info["predicates"]
            @iteration_repetitions[iteration] = info["repetitions"]
            @iteration_actions[iteration] = predicates.to_set
            @iteration_stop_signal[iteration] = info["stop_signal"]
            predicates.each { |p| @action_iteration[p] = iteration }
          end

          @action_iterations_complete = @action_iteration.keys.each_with_object({}) { |p, h| h[p] = 0 }

          @iterations.each do |iteration, info|
            predicates = info["predicates"]
            raise "Iteration predicates count must be even" if predicates.length.odd?
            half = predicates.length / 2
            @half_iteration_actions["#{iteration}_upper"] = predicates[0...half].to_set
            @half_iteration_actions["#{iteration}_lower"] = predicates[half..].to_set
          end

          @half_iteration_actions.each do |half_iteration, preds|
            preds.each { |p| @action_half_iteration[p] = half_iteration }
          end

          @action_requires = @action.transform_values { |a| (a["requires"] || []).to_set }

          half_iteration_requires = @half_iteration_actions.transform_values { Set.new }
          @action_requires.each do |action_name, requires|
            next unless @action_iteration.key?(action_name)
            half_iteration = @action_half_iteration[action_name]
            half_iteration_requires[half_iteration] |= requires
          end

          half_iteration_requires.each do |half_iteration, requires|
            (@half_iteration_actions[half_iteration] || []).each do |predicate|
              next unless @action.key?(predicate)
              @action_requires[predicate] |= (requires - @half_iteration_actions[half_iteration])
            end
          end
        end

        def sort_actions
          actions_to_assign = @config.map { |a| a["name"] }.to_set
          complete = Set.new
          result = []
          assigning_iteration = nil
          exit_for = false
          while actions_to_assign.any?
            remains = actions_to_assign.length
            eligible = if assigning_iteration
              actions_to_assign & @iteration_actions[assigning_iteration]
            else
              actions_to_assign
            end
            eligible.to_a.each do |a|
              if complete >= @action_requires[a]
                result << a
                if @action_iteration.key?(a)
                  assigning_iteration = @action_iteration[a] if assigning_iteration.nil?
                  exit_for = true
                end
                complete << a
                actions_to_assign.delete(a)
                if assigning_iteration && (@iteration_actions[assigning_iteration] & actions_to_assign).empty?
                  assigning_iteration = nil
                end
                if exit_for
                  exit_for = false
                  break
                end
              end
            end
            if actions_to_assign.length == remains
              raise "Could not schedule: #{actions_to_assign.to_a}"
            end
          end
          result
        end

        def action_iteration_stop_signal(action)
          @iteration_stop_signal[@action_iteration[action]]
        end

        def action_iteration_wants_to_stop_by_signal(action)
          signal = action_iteration_stop_signal(action)
          return false if signal.nil? || signal.empty?
          return true if @wrench_in_gears.include?(signal)
          return false unless File.file?(signal)
          content = File.read(signal)
          if content && !content.empty?
            @wrench_in_gears << signal
            true
          else
            false
          end
        end

        def update_state_for_iterative_action(action_name)
          @action_iterations_complete[action_name] += 1
          iteration = @action_iteration[action_name]
          if @action_iterations_complete[action_name] >= @iteration_repetitions[iteration]
            @complete_actions << action_name
          elsif action_iteration_wants_to_stop_by_signal(action_name)
            @complete_actions << action_name
            @action_stopped << action_name
          else
            i = 0
            while i < @actions_to_run.length && @action_iteration[@actions_to_run[i]] == iteration
              i += 1
            end
            @actions_to_run.insert(i, action_name)
          end
        end

        def run_one_action
          action_name = @actions_to_run.shift
          @running_actions << action_name
          @engine.run(@action[action_name]["action"] || {})
          @running_actions.delete(action_name)
          if !@action_iterations_complete.key?(action_name)
            @complete_actions << action_name
          else
            update_state_for_iterative_action(action_name)
          end
        end
      end

      module_function

      def execute_config(config, sql_runner, display_mode: "silent", iterations: {}, final_predicates: [])
        engine = ConcertinaQueryEngine.new(final_predicates, sql_runner, print_running_predicate: display_mode == "colab")
        concertina = Concertina.new(config, engine, display_mode: display_mode, iterations: iterations)
        concertina.run
        engine.final_result
      end
    end
  end
end
