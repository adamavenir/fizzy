require "test_helper"

class BeadsMutationPollerJobTest < ActiveJob::TestCase
  test "job has concurrency limits configured" do
    assert_equal 1, BeadsMutationPollerJob.concurrency_limit
    assert_not_nil BeadsMutationPollerJob.concurrency_key
  end
end
