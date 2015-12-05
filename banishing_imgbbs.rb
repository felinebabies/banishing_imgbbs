# coding: utf-8
# Copyright (C) 2014 Vestalis Quintet シュージ
require 'bundler'
Bundler.require


require_relative './lib/banishingimgdb.rb'

#set :environment, :production

# アップロードできる画像の最大バイト数
IMAGEMAXSIZE = 1 * 1024 * 1024

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

# 削除パスワードが正しいかを判定する
def valid_deletepath?(imgid, deletepass)
	imgdata = BanishingImgDb.getimage(imgid).first

	# 削除パスワードをハッシュ化する
	hashedPass = deletepass.crypt(imgdata['salt'])

	hashedPass == imgdata['deletepassword']
end

class BanishingImgBbs < Sinatra::Base
  register Sinatra::Reloader

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
			# ファイルサイズの確認
			imgFileSize = File.size(params[:file][:tempfile])
			if imgFileSize > IMAGEMAXSIZE then
				@mes = "アップロードできる画像のファイルサイズは#{IMAGEMAXSIZE}バイトまでです。"
				return erb :upload
			end

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

		banishgrace = params[:banishgrace].to_i
		if banishgrace < 0 || banishgrace > 1440 then
			banishgrace = 60
		end

		banishingtype = params[:banishingtype].to_i
		if banishingtype < 0 || banishingtype > 3 then
			banishingtype = 0
		end

		# 画像の読み込みを試行する
		begin
			rgb = Magick::ImageList.new(save_path)
		rescue
			@mes = "アップロードに対応している画像ではありません。"
			return erb :upload
		end

		#サムネイルの作成
		thumb_path = "./public/thumbs/thumb_" + imagename
		rgb.resize_to_fill(80,80).write(thumb_path)

		#データベースへの登録
		imgarr = {
			"imagefilename" => imagename,
			"originalfilename" => params[:file][:filename],
			"timelimit" => timelimit,
			"banishgrace" => banishgrace,
			"banishtype" => banishingtype,
			"ipaddress" => request.ip,
			"comment" => params[:comment],
			"deletepassword" => params[:deletepassword]
		}

		BanishingImgDb.insertimage(imgarr)

		erb :upload
	end

	#アップロードした画像の表示
	get '/view/:imgid' do
		@imgdata = BanishingImgDb.getimage(params[:imgid]).first

		# エラー処理
		if @imgdata == nil then
			status 404
			return body "Image not found."
		end

		erb :viewimg
	end

	#画像ファイルを返す
	get '/image/:imgid' do
		imgdata = BanishingImgDb.getimage(params[:imgid]).first

		# エラー処理
		if imgdata == nil then
			status 404
			return body "Image not found."
		end

		#画像の加工処理
		imgname = getbanishingimg(imgdata)

		content_type MIME::Types.type_for(imgname).first.to_s

		File.binread(imgname)
	end

	# 削除処理
	post '/delete' do
		if valid_deletepath?(params[:id], params[:deletepassword]) then
			BanishingImgDb.setimgalive(0, params[:id])
			@mes = "画像を削除しました。"
		else
			@mes = "削除パスワードに誤りがあるため、画像を削除できません。"
		end

		erb :delete
	end
end
