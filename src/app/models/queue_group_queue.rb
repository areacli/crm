class QueueGroupQueue < ApplicationRecord
  belongs_to :queue_group
  belongs_to :work_queue
end
