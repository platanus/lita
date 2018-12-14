# frozen_string_literal: true

require "forwardable"
require "shellwords"
require 'net/http'
require 'json'

module Lita
  # Represents an incoming chat message.
  class Message
    extend Forwardable

    # The body of the message.
    # @return [String] The message body.
    attr_reader :body

    # The body of the message.
    # @return [String] The message body.
    attr_reader :intent

    # The source of the message, which is a user and optional room.
    # @return [Source] The message source.
    attr_reader :source

    # A hash of arbitrary data that can be populated by Lita adapters and extensions.
    # @return [Hash] The extension data.
    attr_reader :extensions

    # @!method user
    #   The user who sent the message.
    #   @return [User] The user.
    #   @see Source#user
    # @!method room_object
    #   The room where the message came from.
    #   @return [Room] The room.
    #   @see Source#room_object
    #   @since 4.5.0
    # @!method private_message?
    #   Flag indicating that the message was sent to the robot privately.
    #   @return [Boolean] The boolean flag.
    #   @see Source#private_message?
    #   @since 4.5.0
    def_delegators :source, :user, :room_object, :private_message?

    # @param robot [Robot] The currently running robot.
    # @param body [String] The body of the message.
    # @param source [Source] The source of the message.
    def initialize(robot, body, source)
      @robot = robot
      @body = body
      @source = source
      @extensions = {}
      @intent = get_intent

      name_pattern = "@?#{Regexp.escape(@robot.mention_name)}[:,]?\\s+"
      alias_pattern = "#{Regexp.escape(@robot.alias)}\\s*" if @robot.alias
      command_regex = if alias_pattern
        /\A\s*(?:#{name_pattern}|#{alias_pattern})/i
      else
        /\A\s*#{name_pattern}/i
      end

      @body = @body.sub(command_regex) do
        @command = true

        ""
      end
    end

    # An array of arguments created by shellsplitting the message body, as if
    # it were a shell command.
    # @return [Array<String>] The array of arguments.
    def args
      begin
        _command, *args = body.shellsplit
      rescue ArgumentError
        _command, *args =
          body.split(/\s+/).map(&:shellescape).join(" ").shellsplit
      end

      args
    end

    # Marks the message as a command, meaning it was directed at the robot
    # specifically.
    # @return [void]
    def command!
      @command = true
    end

    # A boolean representing whether or not the message was a command.
    # @return [Boolean] +true+ if the message was a command, +false+ if not.
    def command?
      @command
    end

    def get_intent
      uri = URI("http://localhost:5000/parse")
      params = { q: body }
      uri.query = URI.encode_www_form(params)

      res = Net::HTTP.get_response(uri)
      if res.is_a?(Net::HTTPSuccess)
        nlu_response = JSON.parse(res.body)
        intent = nlu_response["intent"]["name"]
        intent&.to_sym
      end
    end

    # An array of matches against the message body for the given {::Regexp}.
    # @param pattern [Regexp] A pattern to match.
    # @return [Array<String>, Array<Array<String>>] An array of matches.
    def match(pattern)
      body.scan(pattern)
    end

    # Replies by sending the given strings back to the source of the message.
    # @param strings [String, Array<String>] The strings to send back.
    # @return [void]
    def reply(*strings)
      @robot.send_messages(source, *strings)
    end

    # Replies by sending the given strings back to the user who sent the
    # message directly, even if the message was sent in a room.
    # @param strings [String, Array<String>] The strings to send back.
    # @return [void]
    def reply_privately(*strings)
      private_source = source.clone
      private_source.private_message!
      @robot.send_messages(private_source, *strings)
    end

    # Replies by sending the given strings back to the source of the message.
    # Each message is prefixed with the user's mention name.
    # @param strings [String, Array<String>] The strings to send back.
    # @return [void]
    # @since 3.1.0
    def reply_with_mention(*strings)
      @robot.send_messages_with_mention(source, *strings)
    end
  end
end
