# frozen_string_literal: true

require "thor"
require "digest"
require "faraday"
require "csv"
require "json"

class Redeemer < Thor
  SECRET = "tB87#kPtkxqOS2"
  ERROR_CODE_TIME_ERROR = 40007
  ERROR_CODE_RECEIVED = 40008
  ERROR_CODE_NOT_LOGIN = 40009
  ERROR_CODE_SAME_TYPE_EXCHANGE = 40011
  ERROR_CODE_CDK_NOT_FOUND = 40014

  desc "player [CSV_FILE]", "Redeem player"
  def player(csv_file)
    rows = CSV.read(csv_file, headers: true)
    updated_rows = []

    rows.each do |row|
      fid = row["fid"]

      begin
        response = login_player(fid)
        data = JSON.parse(response.body)
        if data["code"] == 0
          updated_rows << [
            data["data"]["fid"],
            data["data"]["nickname"],
            data["data"]["kid"],
            data["data"]["stove_lv"],
            data["data"]["total_recharge_amount"]
          ]
          puts "Success for fid: #{fid} nickname: #{data["data"]["nickname"]}"
        else
          puts "Failed for fid: #{fid} code: #{data["code"]} message: #{data["message"]}"
          updated_rows << row.to_h.values
        end
      rescue => e
        puts "Failed for fid: #{fid}"
        puts e
        puts response.body
        updated_rows << row.to_h.values
      end

      sleep(rand(1.0..2.0))
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
      time = Time.now.to_i
      sign = generate_sign({
        cdk: gift_code,
        fid: fid,
        time: time
      })

      response = Faraday.post("https://wos-giftcode-api.centurygame.com/api/gift_code", {
        sign: sign,
        fid: fid,
        cdk: gift_code,
        time: time
      })

      begin
        data = JSON.parse(response.body)
        if data["code"] == 0
          puts "Success for fid: #{fid} nickname: #{data["data"]["nickname"]}"
        else
          puts "Error! Error code: #{data["error_code"]} Message: #{data["msg"]}"
          case data["err_code"]
          when ERROR_CODE_TIME_ERROR
            puts "Gift code #{gift_code} is expired."
            exit
          when ERROR_CODE_RECEIVED
            puts "Gift code #{gift_code} has been redeemed."
            next
          when ERROR_CODE_NOT_LOGIN
            puts "User #{fid} is not logged in."
            exit
          when ERROR_CODE_SAME_TYPE_EXCHANGE
            puts "Gift code #{gift_code} has been redeemed."
            next
          when ERROR_CODE_CDK_NOT_FOUND
            puts "Gift code #{gift_code} is invalid."
            exit
          else
            puts "Unexpected error for fid: #{fid} error code: #{data["error_code"]} message: #{data["msg"]}"
          end
          next
        end
      rescue => e
        puts "Failed for fid: #{fid}"
        puts e
        puts response.body
      ensure
        sleep(rand(1.0..2.0))
      end
    end

    puts "Processing completed."
  end

  private

  def generate_sign(parameters)
    Digest::MD5.hexdigest(parameters.sort.map { |k, v| "#{k}=#{v}" }.join("&") + SECRET)
  end

  def login_player(fid)
    time = Time.now.to_i
    sign = generate_sign({
      fid: fid,
      time: time
    })

    Faraday.post("https://wos-giftcode-api.centurygame.com/api/player", {
      sign: sign,
      fid: fid,
      time: time
    })
  end
end

Redeemer.start(ARGV)
