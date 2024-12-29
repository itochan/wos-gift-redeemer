# frozen_string_literal: true

require "thor"
require "digest"
require "faraday"
require "faraday/retry"
require "csv"
require "json"

class Redeemer < Thor
  SECRET = "tB87#kPtkxqOS2"
  ERROR_CODE_SUCCESS = 20000
  ERROR_CODE_TIMEOUT_RETRY = 40004
  ERROR_CODE_TIME_ERROR = 40007
  ERROR_CODE_RECEIVED = 40008
  ERROR_CODE_NOT_LOGIN = 40009
  ERROR_CODE_SAME_TYPE_EXCHANGE = 40011
  ERROR_CODE_CDK_NOT_FOUND = 40014

  class RedeemError < StandardError; end

  class TimeoutRetryError < RedeemError; end

  class NotLoginError < RedeemError; end

  desc "player [CSV_FILE]", "Redeem player"
  def player(csv_file)
    rows = CSV.read(csv_file, headers: true)
    updated_rows = []

    rows.each do |row|
      fid = row["fid"]

      begin
        response = login_player(fid)
        data = response.body
        if data["code"] == 0
          updated_rows << [
            data["data"]["fid"],
            data["data"]["nickname"],
            data["data"]["kid"],
            data["data"]["stove_lv"],
            data["data"]["total_recharge_amount"]
          ]
          puts "Response code: #{response.status} x-ratelimit-limit: #{response.headers["x-ratelimit-limit"]} x-ratelimit-remaining: #{response.headers["x-ratelimit-remaining"]}"
          puts "Success for fid: #{fid} nickname: #{data["data"]["nickname"]}"
        else
          puts "Response code: #{response.status} x-ratelimit-limit: #{response.headers["x-ratelimit-limit"]} x-ratelimit-remaining: #{response.headers["x-ratelimit-remaining"]}"
          puts "Failed for fid: #{fid} code: #{data["code"]} message: #{data["message"]}"
          updated_rows << row.to_h.values
        end
      rescue Faraday::ClientError => e
        puts "Response code: #{e.response_status} x-ratelimit-limit: #{e.response_headers["x-ratelimit-limit"]} x-ratelimit-remaining: #{e.response_headers["x-ratelimit-remaining"]}"
        puts "Failed for fid: #{fid}"
        puts e.response_body
        puts e
        updated_rows << row.to_h.values
      end
    end

    CSV.open(csv_file, "wb", write_headers: true, headers: rows.headers) do |csv_out|
      updated_rows.each do |updated_row|
        csv_out << updated_row
      end
    end

    puts "Processing completed."
  end

  desc "redeem [CSV_FILE] [GIFT_CODE]", "Redeem code"
  def redeem(csv_file, gift_code)
    rows = CSV.read(csv_file, headers: true)

    rows.each do |row|
      fid = row["fid"]

      login_player(fid)
      sleep(0.5)

      time = Time.now.to_i
      sign = generate_sign({
        cdk: gift_code,
        fid: fid,
        time: time
      })
      response = connection.post("/api/gift_code", {
        sign: sign,
        fid: fid,
        cdk: gift_code,
        time: time
      })

      begin
        puts "Response code: #{response.status} x-ratelimit-limit: #{response.headers["x-ratelimit-limit"]} x-ratelimit-remaining: #{response.headers["x-ratelimit-remaining"]}"
        data = response.body
        if data["code"] == 0
          puts "Success for fid: #{fid} nickname: #{row["nickname"]}"
          puts "Error code: #{data["error_code"]} message: #{data["msg"]}"
        else
          puts "Error user #{fid} #{row["nickname"]} Error code: #{data["err_code"]} Message: #{data["msg"]}"
          case data["err_code"]
          when ERROR_CODE_TIMEOUT_RETRY
            puts "Server is busy. Please try again later."
            raise TimeoutRetryError
          when ERROR_CODE_TIME_ERROR
            puts "Gift code #{gift_code} is expired."
            exit
          when ERROR_CODE_RECEIVED
            puts "Gift code #{gift_code} has been redeemed."
            next
          when ERROR_CODE_NOT_LOGIN
            puts "User #{fid} is not logged in."
            raise NotLoginError
          when ERROR_CODE_SAME_TYPE_EXCHANGE
            puts "Gift code #{gift_code} has been redeemed."
            next
          when ERROR_CODE_CDK_NOT_FOUND
            puts "Gift code #{gift_code} is invalid."
            exit
          else
            puts "Unexpected error for fid: #{fid} error code: #{data["err_code"]} message: #{data["msg"]}"
          end
          next
        end
      rescue => e
        puts "Failed for fid: #{fid}"
        puts e
        puts response.body
      end
    end

    puts "Processing completed."
  end

  private

  def connection
    Faraday.new("https://wos-giftcode-api.centurygame.com") do |f|
      f.request :url_encoded
      f.request :retry, {
        methods: [:get, :post],
        exceptions: [Faraday::ClientError, Faraday::ConnectionFailed, TimeoutRetryError, NotLoginError],
        max: 10,
        interval: 1,
        interval_randomness: 0.5,
        backoff_factor: 2
      }
      f.request :retry, {
        methods: [:get, :post],
        retry_statuses: [429],
        max: 10,
        interval: 1,
        interval_randomness: 0.5,
        backoff_factor: 2
      }
      f.response :raise_error
      f.response :json
    end
  end

  def generate_sign(parameters)
    Digest::MD5.hexdigest(parameters.sort.map { |k, v| "#{k}=#{v}" }.join("&") + SECRET)
  end

  def login_player(fid)
    time = Time.now.to_i
    sign = generate_sign({
      fid: fid,
      time: time
    })

    connection.post("/api/player", {
      sign: sign,
      fid: fid,
      time: time
    })
  end
end

Redeemer.start(ARGV)
