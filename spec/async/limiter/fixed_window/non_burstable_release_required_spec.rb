require "async/limiter/fixed_window"

RSpec.describe Async::Limiter::FixedWindow do
  describe "non burstable, release required" do
    let(:burstable) { false }
    let(:release_required) { true }

    include_examples :fixed_window_limiter

    describe "#async" do
      include_context :async_processing

      context "when processing work in batches" do
        let(:limit) { 4 } # window frame is 1.0 / 4 = 0.25 seconds
        let(:repeats) { 20 }

        def task_duration
          rand * 0.01
        end

        it "checks max number of concurrent task equals 1" do
          expect(maximum).to eq 1
        end

        it "checks the results are in the correct order" do
          expect(result).to eq (0...repeats).to_a
        end

        it "checks max number of tasks in a time window equals the limit" do
          expect(max_per_second).to eq limit
        end
      end

      context "when limit is 1" do
        let(:limit) { 1 }
        let(:repeats) { 3 }
        let(:task_duration) { 0.1 }

        it "executes the tasks sequentially" do
          expect(task_stats).to contain_exactly(
            ["task 0 start", 0],
            ["task 0 end", be_within(50).of(100)],
            ["task 1 start", be_within(50).of(1000)],
            ["task 1 end", be_within(50).of(1100)],
            ["task 2 start", be_within(50).of(2000)],
            ["task 2 end", be_within(50).of(2100)]
          )
        end

        it "ensures max number of tasks in a time window equals the limit" do
          expect(max_per_second).to eq limit
        end
      end

      context "when limit is 3" do
        let(:limit) { 3 } # window_frame is 1.0 / 3 = 0.33
        let(:repeats) { 6 }

        context "when task duration is shorter than window frame" do
          let(:task_duration) { 0.1 }

          it "executes the tasks sequentially" do
            expect(task_stats).to contain_exactly(
              ["task 0 start", 0],
              ["task 0 end", be_within(50).of(100)],
              ["task 1 start", be_within(50).of(333)],
              ["task 1 end", be_within(50).of(433)],
              ["task 2 start", be_within(50).of(666)],
              ["task 2 end", be_within(50).of(766)],
              ["task 3 start", be_within(50).of(1000)],
              ["task 3 end", be_within(50).of(1100)],
              ["task 4 start", be_within(50).of(1333)],
              ["task 4 end", be_within(50).of(1433)],
              ["task 5 start", be_within(50).of(1666)],
              ["task 5 end", be_within(50).of(1766)]
            )
          end
        end

        context "when task duration is longer than window frame" do
          let(:task_duration) { 1.5 }

          # spec with intermittent failures
          it "intermingles task execution" do
            expect(task_stats).to contain_exactly(
              ["task 0 start", 0],
              ["task 1 start", be_within(50).of(333)],
              ["task 2 start", be_within(50).of(666)],
              ["task 0 end", be_within(50).of(1500)], # resumes task 3
              ["task 3 start", be_within(50).of(1500)],
              ["task 1 end", be_within(50).of(1833)], # resumes task 4
              ["task 4 start", be_within(50).of(1833)],
              ["task 2 end", be_within(50).of(2166)], # resumes task 5
              ["task 5 start", be_within(50).of(2166)],
              ["task 3 end", be_within(50).of(3000)],
              ["task 4 end", be_within(50).of(3333)],
              ["task 5 end", be_within(50).of(3666)]
            )
          end
        end
      end
    end

    describe "#blocking?" do
      include_context :blocking_contexts

      before do
        wait_until_next_fixed_window_start
      end

      context "with a default limit" do
        context "when no locks are acquired" do
          include_examples :limiter_is_not_blocking
        end

        context "when a single lock is acquired" do
          include_context :single_lock_is_acquired
          include_examples :limiter_is_blocking

          context "after window passes" do
            before { wait_until_next_window }
            include_examples :limiter_is_blocking
          end
        end

        context "when all the locks are released immediately" do
          include_context :all_locks_are_released_immediately
          include_examples :limiter_is_blocking

          context "after window passes" do
            before { wait_until_next_window }
            include_examples :limiter_is_not_blocking
          end
        end

        context "when no locks are released until the next window" do
          include_context :no_locks_are_released_until_next_window
          include_examples :limiter_is_blocking

          after do
            limiter.release
            expect(limiter).not_to be_blocking
          end
        end
      end

      context "when limit is 2" do
        let(:limit) { 2 }
        let(:window_frame) { window.to_f / limit }

        context "when no locks are acquired" do
          include_examples :limiter_is_not_blocking
        end

        context "when a single lock is acquired" do
          include_context :single_lock_is_acquired
          include_examples :limiter_is_blocking

          context "after window frame passes" do
            before { wait_until_next_window_frame }
            include_examples :limiter_is_not_blocking
          end
        end

        context "when all the locks are acquired" do
          include_context :all_locks_are_acquired
          include_examples :limiter_is_blocking

          context "after window passes" do
            before { wait_until_next_window }
            include_examples :limiter_is_blocking
          end
        end

        context "when all the locks are released immediately" do
          include_context :all_locks_are_released_immediately
          include_examples :limiter_is_blocking

          context "after window passes" do
            before { wait_until_next_window }
            include_examples :limiter_is_not_blocking
          end
        end

        context "when no locks are released until the next window" do
          include_context :no_locks_are_released_until_next_window
          include_examples :limiter_is_blocking
        end
      end
    end
  end
end
