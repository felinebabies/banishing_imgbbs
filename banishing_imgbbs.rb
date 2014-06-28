﻿# coding: utf-8

require "pp"
require "mime/types"
require "sqlite3"
require "securerandom"
require "date"
require "RMagick"
require "sinatra"
require "sinatra/reloader"

#set :environment, :production

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
			banishdirection integer NOT NULL,
			alive integer NOT NULL,
			postipaddress text NOT NULL,
			comment text
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
					?
				)
		SQL

		db = SQLite3::Database.new(DBFILENAME)
		db.execute(insertsql,
			Time.now.strftime("%Y-%m-%d %X"),
			imgarr["imagefilename"],
			imgarr["originalfilename"],
			imgarr["timelimit"],
			imgarr["banishtype"],
			imgarr["banishdirection"],
			1,
			imgarr["ipaddress"],
			imgarr["comment"]
		)
		db.close
	end

	#画像の一覧を取得する
	def getimagelist
		#一覧検索
		selectsql = "SELECT * FROM BANISHINGIMAGE WHERE alive = 1 ORDER BY id DESC"

		self.inittable

		#画像の時間切れ判定を行う

		#検索実行
		db = SQLite3::Database.new(DBFILENAME)
		imagelist = db.execute(selectsql).collect do |row|
			hashrow = {
				"id" => row[0],
				"posttime" => row[1],
				"imagefilename" => row[2],
				"originalfilename" => row[3],
				"timelimit" => row[4],
				"banishtype" => row[5],
				"banishdirection" => row[6],
				"ipaddress" => row[8],
				"comment" => row[9]
			}

			hashrow
		end
		db.close

		return imagelist
	end

	#画像一枚の情報を取得する
	def getimage(imgid)
		#一覧検索
		selectsql = "SELECT * FROM BANISHINGIMAGE WHERE id = ? AND alive = 1"

		self.inittable

		#画像の時間切れ判定を行う

		#検索実行
		db = SQLite3::Database.new(DBFILENAME)
		imagelist = db.execute(selectsql, imgid).collect do |row|
			hashrow = {
				"id" => row[0],
				"posttime" => row[1],
				"imagefilename" => row[2],
				"originalfilename" => row[3],
				"timelimit" => row[4],
				"banishtype" => row[5],
				"banishdirection" => row[6],
				"ipaddress" => row[8],
				"comment" => row[9]
			}

			hashrow
		end
		db.close

		return imagelist
	end

	module_function :createtable
	module_function :tableexists?
	module_function :inittable
	module_function :insertimage
	module_function :getimagelist
	module_function :getimage
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
		"limittime" => limittime,
		"limitminutes" => (limitminutes / (24.0 * 60.0))
	}

	return timeinfo
end

#削除途中画像を生成して、ファイルパスを返す
def getbanishingimg(imgdata)
	timeinfo = getbanishingtimeinfo(imgdata["posttime"], imgdata["timelimit"])

pp timeinfo

	banishingfilename = timeinfo["percent"].to_s + "_" + imgdata["imagefilename"] 

	bimgpath = File.join('banishingimg', banishingfilename)

	#ファイルが存在していたら、そのまま返す
	if File.exist?(bimgpath) then
		return bimgpath
	end

	#削除途中画像を生成する
	imgpath =  File.join('images', imgdata["imagefilename"])
	rgb = Magick::ImageList.new(imgpath).first

	fillheight = (rgb.rows * ((100 - timeinfo["percent"]).to_f / 100.0)).to_i

	Magick::Draw.new do
		self.fill = "black"
	end.rectangle(0, (rgb.rows - fillheight), rgb.columns, rgb.rows).draw(rgb)

	rgb.write(bimgpath)

	return bimgpath
end

#一覧画面
get '/' do
	@imglist = BanishingImgDb.getimagelist
	erb :index
end

#投稿
post '/upload' do
	if params[:file]
		fileext = File.extname(params[:file][:filename])
		imagename = SecureRandom.uuid + fileext
		save_path = "./images/" + imagename
		File.open(save_path, 'wb') do |f|
			p params[:file][:tempfile]
			f.write params[:file][:tempfile].read
			@mes = "アップロードに成功しました。"
		end

		#データベースへの登録
		imgarr = {
			"imagefilename" => imagename,
			"originalfilename" => params[:file][:filename],
			"timelimit" => 180,
			"banishtype" => 0,
			"banishdirection" => 0,
			"ipaddress" => request.ip,
			"comment" => params[:comment]
		}

		BanishingImgDb.insertimage(imgarr)

		#サムネイルの作成
		thumb_path = "./public/thumbs/thumb_" + imagename
		rgb = Magick::ImageList.new(save_path)
		rgb.resize_to_fill(80,80).write(thumb_path)
	else
		@mes = "アップロードに失敗しました。"
	end

	erb :upload
end

#アップロードした画像の表示
get '/view/:imgid' do
	@imgdata = BanishingImgDb.getimage(params[:imgid]).first

	erb :viewimg
end

#画像ファイルを返す
get '/image/:imgid' do
	imgdata = BanishingImgDb.getimage(params[:imgid]).first

	#画像の加工処理
	imgname = getbanishingimg(imgdata)

	content_type MIME::Types.type_for(imgname).first.to_s

	File.binread(imgname)
end
