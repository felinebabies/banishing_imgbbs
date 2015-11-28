# coding: utf-8
# Copyright (C) 2014 Vestalis Quintet シュージ
require 'bundler'
Bundler.require
require "pp"
require "date"
require "securerandom"
require 'digest/sha1'


#データベース操作モジュール
module BanishingImgDb
	DBFILENAME = "banishingimgdb.db"
	#テーブルを作る
	def createtable
		#テーブル定義
		createsql = <<-SQL
		CREATE TABLE BANISHINGIMAGE (
			id integer PRIMARY KEY AUTOINCREMENT NOT NULL,
			posttime text NOT NULL,
			imagefilename text NOT NULL,
			originalfilename text NOT NULL,
			timelimit integer NOT NULL,
			banishtype integer NOT NULL,
			alive integer NOT NULL,
			postipaddress text NOT NULL,
			comment text,
			salt text,
			deletepassword text
		);
		SQL
		db = SQLite3::Database.new(DBFILENAME)

		db.execute_batch(createsql)

		db.close
	end

	#必要なテーブルがあるかを確認する
	def tableexists?
		db = SQLite3::Database.new(DBFILENAME)
		tables = db.execute("SELECT tbl_name FROM sqlite_master WHERE type == 'table'").flatten

		reqarr = tables.select do |tablename|
			tablename == "BANISHINGIMAGE"
		end

		result = false
		if ! reqarr.empty? then
			result = true
		end

		db.close

		return result
	end

	#テーブルが無ければ作る
	def inittable
		if ! self.tableexists? then
			self.createtable
		end
	end

	#画像を新しく登録する
	def insertimage(imgarr)
		self.inittable
		insertsql = <<-SQL
			INSERT INTO BANISHINGIMAGE
				VALUES (
					NULL,
					?,
					?,
					?,
					?,
					?,
					?,
					?,
					?,
					?,
					?
				)
		SQL

		# saltを生成する
		salt = self.generate_salt

		# 削除パスワードをハッシュ化する
		hashedPass = imgarr["deletepassword"].crypt(salt)

		db = SQLite3::Database.new(DBFILENAME)
		db.execute(insertsql,
			Time.now.strftime("%Y-%m-%d %X"),
			imgarr["imagefilename"],
			imgarr["originalfilename"],
			imgarr["timelimit"],
			imgarr["banishtype"],
			1,
			imgarr["ipaddress"],
			imgarr["comment"],
			salt,
			hashedPass
		)
		db.close
	end

	#select文の結果を画像情報ハッシュに変換する
	def getimgdatafromrow(row)
		hashrow = {
			"id" => row[0],
			"posttime" => row[1],
			"imagefilename" => row[2],
			"originalfilename" => row[3],
			"timelimit" => row[4],
			"banishtype" => row[5],
			"ipaddress" => row[7],
			"comment" => row[8],
			"salt" => row[9],
			"deletepassword" => row[10]
		}

		#残時間情報を追加する
		timeinfo = self.getbanishingtimeinfo(hashrow["posttime"], hashrow["timelimit"])
		hashrow["percent"] = timeinfo["percent"]
		hashrow["leftminutes"] = timeinfo["leftminutes"]
		hashrow["limittime"] = timeinfo["limittime"]

		return hashrow
	end

	#時間切れの画像をリストとDBから削除する
	def filteraliveimg(imagelist)
		alivelist = imagelist.select do |imgdata|
			aliveflag = true

			if imgdata["percent"] <= 0 then
				setimgalive(0, imgdata["id"])
				aliveflag = false
			end

			aliveflag
		end

		return alivelist
	end

	#画像の一覧を取得する
	def getimagelist
		#一覧検索
		selectsql = "SELECT * FROM BANISHINGIMAGE WHERE alive = 1 ORDER BY id DESC"

		self.inittable

		#検索実行
		db = SQLite3::Database.new(DBFILENAME)
		imagelist = db.execute(selectsql).collect do |row|
			self.getimgdatafromrow(row)
		end
		db.close

		#画像の時間切れ判定を行う
		alivelist = self.filteraliveimg(imagelist)

		return alivelist
	end

	#画像一枚の情報を取得する
	def getimage(imgid)
		#一覧検索
		selectsql = "SELECT * FROM BANISHINGIMAGE WHERE id = ? AND alive = 1"

		self.inittable

		#検索実行
		db = SQLite3::Database.new(DBFILENAME)
		imagelist = db.execute(selectsql, imgid).collect do |row|
			self.getimgdatafromrow(row)
		end
		db.close

		#画像の時間切れ判定を行う
		alivelist = self.filteraliveimg(imagelist)

		return alivelist
	end

	#画像の有効情報を変更する
	def setimgalive(alive, imgid)
		updatesql = "UPDATE BANISHINGIMAGE SET alive = ? WHERE id = ?"

		#アップデート実行
		db = SQLite3::Database.new(DBFILENAME)
		db.execute(updatesql,
			alive,
			imgid
		)
		db.close
	end

	#時刻情報を返す
	def getbanishingtimeinfo(posttime, timelimitmin)
		#画像投稿時刻を取得
		posttime = DateTime.parse(posttime + "+9:00")

		#時間制限（分単位）を取得
		limitminutes = timelimitmin.to_f

		#画像消滅予定時刻を生成
		limittime = posttime + (limitminutes / (24.0 * 60.0))

		#消滅予定時刻との差を分で生成
		diffminutes = ((limittime - DateTime.now) * 24.0 * 60.0).to_i

		#パーセンテージを計算する
		if diffminutes <= 0 then
			percent = 0
		else
			percent = ((diffminutes / limitminutes) * 100).to_i
		end

		timeinfo = {
			"percent" => percent,
			"leftminutes" => diffminutes,
			"limittime" => limittime.strftime("%Y-%m-%d %X")
		}

		return timeinfo
	end

	def generate_salt
	  Digest::SHA1.hexdigest("#{Time.now.to_s}")
	end

	module_function :createtable
	module_function :tableexists?
	module_function :inittable
	module_function :insertimage
	module_function :getimgdatafromrow
	module_function :filteraliveimg
	module_function :getimagelist
	module_function :getimage
	module_function :setimgalive
	module_function :getbanishingtimeinfo
	module_function :generate_salt
end
