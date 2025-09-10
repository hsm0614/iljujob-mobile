// 📁 controllers/clientController.js
const db = require('../models/db');
const jwt = require('jsonwebtoken');
require('dotenv').config();
const SECRET = process.env.JWT_SECRET;

exports.clientSignup = async (req, res) => {
  const { phone, manager } = req.body;

  if (!phone) {
    return res.status(400).json({ success: false, message: '전화번호는 필수입니다.' });
  }

  try {
    let clientId;
    const [existingClients] = await db.query('SELECT * FROM clients WHERE phone = ?', [phone]);

    if (existingClients.length > 0) {
      clientId = existingClients[0].id;
    } else {
      const [insertResult] = await db.query(
        'INSERT INTO clients (phone, manager_name) VALUES (?, ?)',
        [phone, manager]
      );
      clientId = insertResult.insertId;
    }

    const token = jwt.sign({ id: clientId, phone, role: 'client' }, SECRET, { expiresIn: '7d' });

    return res.status(200).json({
      success: true,
      token,
      id: clientId,
      phone,
    });
  } catch (err) {
    console.error('❌ clientSignup 오류:', err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
};

exports.clientCheck = async (req, res) => {
  const { phone } = req.body;
  console.log(`📥 [${new Date().toISOString()}] /api/client/check 요청 받음: ${phone}`); // 요청 받음 로그 추가
  if (!phone) {
    return res.status(400).json({ success: false, message: '전화번호가 필요합니다.' });
  }

  try {
    const [results] = await db.query('SELECT * FROM clients WHERE phone = ?', [phone]);

    if (results.length > 0) {
      const clientId = results[0].id;
      const token = jwt.sign({ id: clientId, phone, role: 'client' }, SECRET, { expiresIn: '7d' });
      return res.status(200).json({
        success: true,
        exists: true,  // ✅ 추가
        token,
        id: clientId,
        phone,
        message: '기존 사용자',
      });
    } else {
      return res.status(200).json({
        success: true,
        exists: false,
        message: '사용자 없음',
      });
    }
  } catch (err) {
    console.error('❌ clientCheck 오류:', err);
    return res.status(500).json({ success: false, message: 'DB 오류' });
  }
};

exports.getSummary = async (req, res) => {
  const clientPhone = req.query.clientPhone;

  try {
    // 오늘
    const [todayRows] = await db.query(`
      SELECT COUNT(*) AS count
      FROM applications a
      JOIN jobs j ON a.job_id = j.id
      WHERE j.userNumber = ? AND DATE(a.applied_at) = CURDATE()
    `, [clientPhone]);

    // 이번 주
    const [weekRows] = await db.query(`
      SELECT COUNT(*) AS count
      FROM applications a
      JOIN jobs j ON a.job_id = j.id
      WHERE j.userNumber = ? AND YEARWEEK(a.applied_at, 1) = YEARWEEK(CURDATE(), 1)
    `, [clientPhone]);

    // 이번 달
    const [monthRows] = await db.query(`
      SELECT COUNT(*) AS count
      FROM applications a
      JOIN jobs j ON a.job_id = j.id
      WHERE j.userNumber = ? AND YEAR(a.applied_at) = YEAR(CURDATE()) AND MONTH(a.applied_at) = MONTH(CURDATE())
    `, [clientPhone]);

    res.json({
      todayApplicants: todayRows[0].count,
      weekApplicants: weekRows[0].count,
      monthApplicants: monthRows[0].count,
    });
  } catch (err) {
    console.error('❌ 요약 데이터 조회 실패:', err);
    res.status(500).send('서버 오류');
  }
};



// GET: 프로필 불러오기
exports.getProfile = async (req, res) => {
    const { phone } = req.query;
    try {
        const [rows] = await db.query(
            'SELECT phone, manager_name, company_name, email, description, logo_url FROM clients WHERE phone = ?',
            [phone]
        );
        if (rows.length === 0) {
            return res.status(404).json({ message: '회원 정보를 찾을 수 없습니다.' });
        }
        res.json(rows[0]);
    } catch (err) {
        console.error('❌ getProfile 오류:', err);
        res.status(500).json({ message: '서버 오류' });
    }
};

// PATCH: 프로필 수정
exports.updateProfile = async (req, res) => {
    const { phone, manager_name, company_name, email, description, logo_url } = req.body;
    try {
        const [result] = await db.query(
            'UPDATE clients SET manager_name = ?, company_name = ?, email = ?, description = ?, logo_url = ?, updated_at = NOW() WHERE phone = ?',
            [manager_name, company_name, email, description, logo_url, phone]
        );
        if (result.affectedRows === 0) {
            return res.status(404).json({ message: '회원 정보를 찾을 수 없습니다.' });
        }
        res.json({ message: '프로필이 수정되었습니다.' });
    } catch (err) {
        console.error('❌ updateProfile 오류:', err);
        res.status(500).json({ message: '서버 오류' });
    }
};
// DELETE: 회원 탈퇴
exports.deleteProfile = async (req, res) => {
    const { phone } = req.query;
    try {
        const [result] = await db.query('DELETE FROM clients WHERE phone = ?', [phone]);
        if (result.affectedRows === 0) {
            return res.status(404).json({ message: '회원 정보를 찾을 수 없습니다.' });
        }
        res.json({ message: '회원 탈퇴가 완료되었습니다.' });
    } catch (err) {
        console.error('❌ deleteProfile 오류:', err);
        res.status(500).json({ message: '서버 오류' });
    }
};