# coding: utf-8
# Copyright (C) 2014 Vestalis Quintet シュージ
require "pp"
require "mime/types"
require "sqlite3"
require "securerandom"
require "date"
require "RMagick"
require "sinatra"
require "sinatra/reloader"

require File.dirname(__FILE__) + '/banishingimgdb.rb'

#set :environment, :production

#削除途中画像を生成して、ファイルパスを返す
def getbanishingimg(imgdata)

	banishingfilename = imgdata["percent"].to_s + "_" + imgdata["imagefilename"] 

	bimgpath = File.join('banishingimg', banishingfilename)

	#ファイルが存在していたら、そのまま返す
	if File.exist?(bimgpath) then
		return bimgpath
	end

	#削除途中画像を生成する
	imgpath =  File.join('images', imgdata["imagefilename"])
	rgb = Magick::ImageList.new(imgpath).first

	fillheight = (rgb.rows * ((100 - imgdata["percent"]).to_f / 100.0)).to_i

	#背景画像を用意
	bgimage = Magick::ImageList.new("background.png").first

	Magick::Draw.new do
		self.fill_pattern = bgimage
	end.rectangle(0, (rgb.rows - fillheight), rgb.columns, rgb.rows).draw(rgb)

	rgb.write(bimgpath)

	return bimgpath
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

#ヘルパー定義
helpers do
	#サニタイズ用関数を使用する用意
	include Rack::Utils
	alias_method :h, :escape_html
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

		#制限時間の取得
		timelimit = params[:timelimitmin].to_i
		if timelimit < 60 || timelimit > 1440 then
			timelimit = 180
		end

		#データベースへの登録
		imgarr = {
			"imagefilename" => imagename,
			"originalfilename" => params[:file][:filename],
			"timelimit" => timelimit,
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
