﻿# coding: utf-8
# Copyright (C) 2014 Vestalis Quintet シュージ
require 'bundler'
Bundler.require


require_relative './lib/banishingimgdb.rb'

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

	#消滅種類ごとに画像を生成する
	case imgdata["banishtype"]
	when 0
		# 下から徐々に消していく
		fillheight = (rgb.rows * ((100 - imgdata["percent"]).to_f / 100.0)).to_i

		#背景画像を用意
		bgimage = Magick::ImageList.new("background.png").first

		Magick::Draw.new do
			self.fill_pattern = bgimage
		end.rectangle(0, (rgb.rows - fillheight), rgb.columns, rgb.rows).draw(rgb)
	when 1
		# 上から徐々に消していく
		fillheight = (rgb.rows * ((100 - imgdata["percent"]).to_f / 100.0)).to_i

		#背景画像を用意
		bgimage = Magick::ImageList.new("background.png").first

		Magick::Draw.new do
			self.fill_pattern = bgimage
		end.rectangle(0, 0, rgb.columns, fillheight).draw(rgb)
	when 2
		# 左から徐々に消していく
		fillwidth = (rgb.columns * ((100 - imgdata["percent"]).to_f / 100.0)).to_i

		#背景画像を用意
		bgimage = Magick::ImageList.new("background.png").first

		Magick::Draw.new do
			self.fill_pattern = bgimage
		end.rectangle(0, 0, fillwidth, rgb.rows).draw(rgb)
	when 3
		# 右から徐々に消していく
		fillwidth = (rgb.columns * ((100 - imgdata["percent"]).to_f / 100.0)).to_i

		#背景画像を用意
		bgimage = Magick::ImageList.new("background.png").first

		Magick::Draw.new do
			self.fill_pattern = bgimage
		end.rectangle((rgb.columns - fillwidth), 0, rgb.columns, rgb.rows).draw(rgb)
	else
		#想定外の消し方が指定された
	end


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
	#コメントの長さ制限
	if params[:comment].length > 1000 then
		@mes = "コメントは1000文字以下でお願いします。"

		return erb :upload
	end

	if params[:file]
		fileext = File.extname(params[:file][:filename])
		imagename = SecureRandom.uuid + fileext
		save_path = "./images/" + imagename
		File.open(save_path, 'wb') do |f|
			p params[:file][:tempfile]
			f.write params[:file][:tempfile].read
			@mes = "アップロードに成功しました。"
		end
	else
		@mes = "アップロードに失敗しました。"
		return erb :upload
	end

	#制限時間の取得
	timelimit = params[:timelimitmin].to_i
	if timelimit < 60 || timelimit > 1440 then
		timelimit = 180
	end

	banishingtype = params[:banishingtype].to_i
	if banishingtype < 0 || banishingtype > 3 then
		banishingtype = 0
	end

	#データベースへの登録
	imgarr = {
		"imagefilename" => imagename,
		"originalfilename" => params[:file][:filename],
		"timelimit" => timelimit,
		"banishtype" => banishingtype,
		"ipaddress" => request.ip,
		"comment" => params[:comment]
	}

	BanishingImgDb.insertimage(imgarr)

	#サムネイルの作成
	thumb_path = "./public/thumbs/thumb_" + imagename
	rgb = Magick::ImageList.new(save_path)
	rgb.resize_to_fill(80,80).write(thumb_path)

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
