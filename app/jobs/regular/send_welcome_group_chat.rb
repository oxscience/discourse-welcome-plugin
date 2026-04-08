# frozen_string_literal: true

module Jobs
  class SendWelcomeGroupChat < ::Jobs::Base
    def execute(args)
      return unless defined?(Chat)

      sender = User.find_by(id: args[:sender_id])
      channel = Chat::Channel.find_by(id: args[:channel_id])
      return unless sender && channel

      Chat::MessageCreator.create(
        chat_channel: channel,
        user: sender,
        content: args[:message]
      )
    rescue => e
      Rails.logger.warn("DiscourseWelcome: Failed to send group chat: #{e.message}")
    end
  end
end
