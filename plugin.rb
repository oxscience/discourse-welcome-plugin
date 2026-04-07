# frozen_string_literal: true

# name: discourse-welcome
# about: Sends a personal welcome PM from a specified user when new users register, and posts a welcome message in group chat channels when users join groups.
# version: 0.1.0
# authors: Pat
# url: https://github.com/oxscience/discourse-welcome-plugin
# required_version: 2.7.0

enabled_site_setting :welcome_plugin_enabled

after_initialize do
  module ::DiscourseWelcome
    PLUGIN_NAME = "discourse-welcome"
  end

  # ===========================================
  # 1) Welcome PM when a new user is activated
  # ===========================================
  on(:user_activated) do |user|
    next unless SiteSetting.welcome_plugin_enabled
    next unless SiteSetting.welcome_pm_enabled

    sender_username = SiteSetting.welcome_pm_sender_username
    sender = User.find_by(username_lower: sender_username.downcase)
    next unless sender

    title = SiteSetting.welcome_pm_title
      .gsub("{username}", user.username)
      .gsub("{name}", user.name.presence || user.username)

    body = SiteSetting.welcome_pm_body
      .gsub("{username}", user.username)
      .gsub("{name}", user.name.presence || user.username)

    # Send the PM after a short delay so user has time to land
    Jobs.enqueue_in(
      SiteSetting.welcome_pm_delay_minutes.minutes,
      :send_welcome_pm,
      user_id: user.id,
      sender_id: sender.id,
      title: title,
      body: body
    )
  end

  # ===========================================
  # 2) Welcome chat message when user joins group
  # ===========================================
  on(:user_added_to_group) do |user, group, opts|
    next unless SiteSetting.welcome_plugin_enabled
    next unless SiteSetting.welcome_group_chat_enabled

    # Skip if group has no associated chat channel
    next unless defined?(Chat)

    sender_username = SiteSetting.welcome_pm_sender_username
    sender = User.find_by(username_lower: sender_username.downcase)
    next unless sender

    # Find chat channel associated with this group
    channel = Chat::Channel.where(
      chatable_type: "Category"
    ).or(
      Chat::Channel.where(chatable_type: "DirectMessage")
    ).find_by(
      "name ILIKE ? OR slug ILIKE ?",
      "%#{group.name}%",
      "%#{group.name}%"
    )

    # Alternative: check if group has a dedicated channel via group setting
    if channel.nil?
      channel = Chat::Channel.find_by(chatable_type: "Category", chatable_id: group.id) rescue nil
    end

    next unless channel

    message = SiteSetting.welcome_group_chat_message
      .gsub("{username}", user.username)
      .gsub("{name}", user.name.presence || user.username)
      .gsub("{group}", group.full_name.presence || group.name)

    Jobs.enqueue_in(
      1.minute,
      :send_welcome_group_chat,
      user_id: user.id,
      sender_id: sender.id,
      channel_id: channel.id,
      message: message
    )
  end

  # ===========================================
  # Job: Send Welcome PM
  # ===========================================
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
end
