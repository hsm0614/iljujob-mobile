// 📁 controllers/workerController.js
const fetch = require('node-fetch');
const jwt = require('jsonwebtoken');
require('dotenv').config();
const uuid = require('uuid');
const db = require('../models/db');
const path = require('path');

const SECRET = process.env.JWT_SECRET;
const BASE_URL = process.env.BASE_URL || 'http://localhost:3000';

// 회원가입
exports.workerSignup = async (req, res) => {
  const { phone, gender, birthYear, strengths, traits, userType } = req.body;
  if (!phone) return res.status(400).json({ success: false, message: '전화번호는 필수입니다.' });

  try {
    const [existingUsers] = await db.query('SELECT * FROM workers WHERE phone = ?', [phone]);

    let userId;
    if (existingUsers.length > 0) {
      userId = existingUsers[0].id;
    } else {
      const strengthsStr = Array.isArray(strengths) ? strengths.join(',') : strengths;
      const traitsStr = Array.isArray(traits) ? traits.join(',') : traits;

      const [insertResult] = await db.query(
        'INSERT INTO workers (phone, gender, birth_year, strengths, traits, user_type) VALUES (?, ?, ?, ?, ?, ?)',
        [phone, gender, birthYear, strengthsStr, traitsStr, userType]
      );
      userId = insertResult.insertId;
    }

    const token = jwt.sign({ id: userId, phone, role: 'worker' }, SECRET, { expiresIn: '7d' });

    return res.status(200).json({ success: true, token, id: userId, phone });
  } catch (err) {
    console.error('❌ workerSignup 오류:', err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
};

// 전화번호 중복 확인
exports.workerCheck = async (req, res) => {
  const { phone } = req.body;
  if (!phone) return res.status(400).json({ success: false, message: '전화번호가 필요합니다.' });

  try {
    const [results] = await db.query('SELECT * FROM workers WHERE phone = ?', [phone]);
    if (results.length > 0) {
      const userId = results[0].id;
      const token = jwt.sign({ id: userId, phone, role: 'worker' }, SECRET, { expiresIn: '7d' });
      return res.status(200).json({ success: true, exists: true, token, id: userId, message: '기존 사용자' });
    } else {
      return res.status(200).json({ success: true, exists: false, message: '사용자 없음' });
    }
  } catch (err) {
    console.error('❌ workerCheck 오류:', err);
    return res.status(500).json({ success: false, message: 'DB 오류' });
  }
};

// 본인 인증 요청
exports.workerRequestIdentityVerification = async (req, res) => {
  
  const storeId = process.env.PORTONE_STORE_ID;
  const channelKey = process.env.PORTONE_CHANNEL_KEY;
  const identityVerificationId = `identity-verification-${uuid.v4()}`;

  try {
    console.log('📡 본인 인증 요청 도착:', req.body);
    const response = await fetch('https://api.portone.io/identity-verifications', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ storeId, identityVerificationId, channelKey }),
    });

    if (response.status !== 200) return res.status(500).json({ success: false, message: '본인 인증 요청 실패' });
    const verificationData = await response.json();
    return res.status(200).json({ success: true, identityVerificationId });
  } catch (err) {
    console.error('❌ 본인 인증 요청 실패:', err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
};

// 프로필 조회
exports.getProfile = async (req, res) => {
  const { phone } = req.query;
  try {
    const [rows] = await db.query(
      `SELECT id, phone, name, gender, birth_year, strengths, traits,
              desired_work, available_days, available_times,
              introduction, experience, profile_image_url, user_type, created_at
       FROM workers WHERE phone = ?`,
      [phone]
    );
    if (rows.length === 0) return res.status(404).json({ message: '회원 정보를 찾을 수 없습니다.' });
    res.json(rows[0]);
  } catch (err) {
    console.error('❌ getProfile 오류:', err);
    res.status(500).json({ message: '서버 오류' });
  }
};

// 프로필 수정
exports.updateProfile = async (req, res) => {
  const {
    phone, name, gender, birth_year, strengths, traits,
    desired_work, available_days, available_times,
    introduction, experience
  } = req.body;

  try {
    const [result] = await db.query(
      `UPDATE workers SET
        name = ?, gender = ?, birth_year = ?, strengths = ?, traits = ?,
        desired_work = ?, available_days = ?, available_times = ?,
        introduction = ?, experience = ?
       WHERE phone = ?`,
      [name, gender, birth_year, strengths, traits, desired_work, available_days, available_times, introduction, experience, phone]
    );

    if (result.affectedRows === 0) return res.status(404).json({ message: '회원 정보를 찾을 수 없습니다.' });
    res.json({ message: '프로필이 수정되었습니다.' });
  } catch (err) {
    console.error('❌ updateProfile 오류:', err);
    res.status(500).json({ message: '서버 오류' });
  }
};

// 프로필 이미지 업로드 핸들러
exports.uploadProfileImage = async (req, res) => {
  const { phone, name, desired_work, strengths, available_days, available_times, introduction, experience } = req.body;
  const filePath = req.file?.path;

  if (!phone) return res.status(400).json({ success: false, message: '전화번호 누락' });

  const imageUrl = filePath ? `${BASE_URL}/${filePath.replace(/\\/g, '/')}` : null;

  try {
    const [result] = await db.query(
      `UPDATE workers SET
        ${imageUrl ? 'profile_image_url = ?,' : ''}
        name = ?, desired_work = ?, strengths = ?, available_days = ?, available_times = ?, introduction = ?, experience = ?
       WHERE phone = ?`,
      imageUrl
        ? [imageUrl, name, desired_work, strengths, available_days, available_times, introduction, experience, phone]
        : [name, desired_work, strengths, available_days, available_times, introduction, experience, phone]
    );

    if (result.affectedRows === 0) return res.status(404).json({ success: false, message: '회원 정보를 찾을 수 없습니다.' });
    res.json({ success: true, ...(imageUrl ? { imageUrl } : {}) });
  } catch (err) {
    console.error('❌ 프로필 업데이트 실패:', err);
    res.status(500).json({ success: false, message: '서버 오류' });
  }
};
// 회원 탈퇴
exports.deleteProfile = async (req, res) => {
  const { phone } = req.query;
  try {
    const [result] = await db.query('DELETE FROM workers WHERE phone = ?', [phone]);
    if (result.affectedRows === 0) return res.status(404).json({ message: '회원 정보를 찾을 수 없습니다.' });
    res.json({ message: '회원 탈퇴가 완료되었습니다.' });
  } catch (err) {
    console.error('❌ deleteProfile 오류:', err);
    res.status(500).json({ message: '서버 오류' });
  }
};
