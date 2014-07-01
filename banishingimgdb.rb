# coding: utf-8
# Copyright (C) 2014 Vestalis Quintet �V���[�W


#�f�[�^�x�[�X���샂�W���[��
module BanishingImgDb
	DBFILENAME = "banishingimgdb.db"
	#�e�[�u�������
	def createtable
		#�e�[�u����`
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

	#�K�v�ȃe�[�u�������邩���m�F����
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

	#�e�[�u����������΍��
	def inittable
		if ! self.tableexists? then
			self.createtable
		end
	end

	#�摜��V�����o�^����
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

	#select���̌��ʂ��摜���n�b�V���ɕϊ�����
	def getimgdatafromrow(row)
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

		#�c���ԏ���ǉ�����
		timeinfo = self.getbanishingtimeinfo(hashrow["posttime"], hashrow["timelimit"])
		hashrow["percent"] = timeinfo["percent"]
		hashrow["leftminutes"] = timeinfo["leftminutes"]
		hashrow["limittime"] = timeinfo["limittime"]

		return hashrow
	end

	#�摜�̈ꗗ���擾����
	def getimagelist
		#�ꗗ����
		selectsql = "SELECT * FROM BANISHINGIMAGE WHERE alive = 1 ORDER BY id DESC"

		self.inittable

		#�������s
		db = SQLite3::Database.new(DBFILENAME)
		imagelist = db.execute(selectsql).collect do |row|
			self.getimgdatafromrow(row)
		end
		db.close

		#�摜�̎��Ԑ؂ꔻ����s��
		alivelist = filteraliveimg(imagelist)

		return alivelist
	end

	#�摜�ꖇ�̏����擾����
	def getimage(imgid)
		#�ꗗ����
		selectsql = "SELECT * FROM BANISHINGIMAGE WHERE id = ? AND alive = 1"

		self.inittable

		#�������s
		db = SQLite3::Database.new(DBFILENAME)
		imagelist = db.execute(selectsql, imgid).collect do |row|
			self.getimgdatafromrow(row)
		end
		db.close

		#�摜�̎��Ԑ؂ꔻ����s��
		alivelist = filteraliveimg(imagelist)

		return alivelist
	end

	#�摜�̗L������ύX����
	def setimgalive(alive, imgid)
		updatesql = "UPDATE BANISHINGIMAGE SET alive = ? WHERE id = ?"

		#�A�b�v�f�[�g���s
		db = SQLite3::Database.new(DBFILENAME)
		db.execute(updatesql,
			alive,
			imgid
		)
		db.close
	end

	#��������Ԃ�
	def getbanishingtimeinfo(posttime, timelimitmin)
		#�摜���e�������擾
		posttime = DateTime.parse(posttime + "+9:00")

		#���Ԑ����i���P�ʁj���擾
		limitminutes = timelimitmin.to_f

		#�摜���ŗ\�莞���𐶐�
		limittime = posttime + (limitminutes / (24.0 * 60.0))

		#���ŗ\�莞���Ƃ̍��𕪂Ő���
		diffminutes = ((limittime - DateTime.now) * 24.0 * 60.0).to_i

		#�p�[�Z���e�[�W���v�Z����
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

	module_function :createtable
	module_function :tableexists?
	module_function :inittable
	module_function :insertimage
	module_function :getimgdatafromrow
	module_function :getimagelist
	module_function :getimage
	module_function :setimgalive
	module_function :getbanishingtimeinfo
end
