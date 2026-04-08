# frozen_string_literal: true

module Jobs
  class SendWelcomePm < ::Jobs::Base
    def execute(args)
      user = User.find_by(id: args[:user_id])
      sender = User.find_by(id: args[:sender_id])
      return unless user && sender

      PostCreator.create!(
        sender,
        title: args[:title],
        raw: args[:body],
        archetype: Archetype.private_message,
        target_usernames: [user.username],
        skip_validations: true
      )
    end
  end
end
