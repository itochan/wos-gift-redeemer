# frozen_string_literal: true

require "thor"
require "digest"
require "faraday"
require "csv"
require "json"

class Redeemer < Thor
  SECRET = "tB87#kPtkxqOS2"

  desc "player [CSV_FILE]", "Redeem player"
  def player(csv_file)
    rows = CSV.read(csv_file, headers: true)
    updated_rows = []

    rows.each do |row|
      fid = row["fid"]
      time = Time.now.to_i
      sign = generate_sign({
        fid: fid,
        time: time
      })

      response = Faraday.post("https://wos-giftcode-api.centurygame.com/api/player", {
        fid: fid,
        time: time,
        sign: sign
      })

      begin
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

  private

  def generate_sign(parameters)
    Digest::MD5.hexdigest(parameters.sort.map { |k, v| "#{k}=#{v}" }.join("&") + SECRET)
  end
end

Redeemer.start(ARGV)
