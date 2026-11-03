class QueueGroupUser < ApplicationRecord
  belongs_to :queue_group
  belongs_to :user
end
