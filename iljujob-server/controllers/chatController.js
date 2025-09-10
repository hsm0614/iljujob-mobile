// 📁 iljujob-server/controllers/chatController.js
const db = require('../models/db');

// 🔹 채팅방 생성 (또는 기존 채팅방 반환)
exports.startChat = async (req, res) => {
  const { userPhone, jobId, clientPhone } = req.body;

  if (!userPhone || !jobId || !clientPhone) {
    return res.status(400).json({ message: '필수 항목 누락' });
  }

  try {
    // 1️⃣ 기존 채팅방 확인
    const [existing] = await db.query(
      `SELECT id FROM chat_rooms WHERE user_phone = ? AND job_id = ? AND client_phone = ?`,
      [userPhone, jobId, clientPhone]
    );

    if (existing.length > 0) {
      return res.status(200).json({ roomId: existing[0].id });
    }

    // 2️⃣ 없으면 새로 생성
    const [insertResult] = await db.query(
      `INSERT INTO chat_rooms (user_phone, job_id, client_phone) VALUES (?, ?, ?)`,
      [userPhone, jobId, clientPhone]
    );

    return res.status(201).json({ roomId: insertResult.insertId });
  } catch (err) {
    console.error('❌ 채팅방 생성 오류:', err);
    return res.status(500).json({ message: '서버 오류' });
  }
};

exports.getChatList = async (req, res) => {
  const { userPhone, userType } = req.query;

  if (!userPhone || !userType) {
    return res.status(400).json({ message: 'userPhone과 userType이 필요합니다.' });
  }

  try {
    let sql = '';
    let param = [userPhone];

    if (userType === 'worker') {
  sql = `
    SELECT 
      cr.*,
      j.title AS job_title,
      j.pay,
      j.created_at,
      c.company_name AS client_company_name,
      c.logo_url AS client_thumbnail_url,           -- 기업 썸네일
      c.phone AS client_phone,
      u.name AS user_name,
      u.profile_image_url AS user_thumbnail_url,    -- 구직자 썸네일
      u.phone AS user_phone
    FROM chat_rooms cr
    JOIN jobs j ON cr.job_id = j.id
    JOIN clients c ON cr.client_phone = c.phone
    JOIN workers u ON cr.user_phone = u.phone
    WHERE cr.user_phone = ? AND cr.is_active = 1
    ORDER BY cr.last_sent_at DESC
  `;
} else if (userType === 'client') {
  sql = `
    SELECT 
      cr.*,
      j.title AS job_title,
      j.pay,
      j.created_at,
      c.company_name AS client_company_name,
      c.logo_url AS client_thumbnail_url,           -- 기업 썸네일
      c.phone AS client_phone,
      u.name AS user_name,
      u.profile_image_url AS user_thumbnail_url,    -- 구직자 썸네일
      u.phone AS user_phone
    FROM chat_rooms cr
    JOIN jobs j ON cr.job_id = j.id
    JOIN clients c ON cr.client_phone = c.phone
    JOIN workers u ON cr.user_phone = u.phone
    WHERE cr.client_phone = ? AND cr.is_active = 1
    ORDER BY cr.last_sent_at DESC
  `;
} else {
      return res.status(400).json({ message: 'userType은 worker 또는 client여야 합니다.' });
    }

    const [results] = await db.query(sql, param);
    res.json(results);
  } catch (err) {
    console.error('❌ 채팅방 목록 조회 실패:', err);
    res.status(500).json({ message: 'DB 오류' });
  }
};

// 🔹 내가 속한 채팅방 간단 리스트
exports.getChatRooms = async (req, res) => {
  const { userPhone } = req.query;

  if (!userPhone) {
    return res.status(400).json({ message: 'userPhone 필수' });
  }

  try {
    const [results] = await db.query(
      `SELECT id, job_id, client_phone FROM chat_rooms WHERE user_phone = ? ORDER BY id DESC`,
      [userPhone]
    );

    res.json(results);
  } catch (err) {
    console.error('❌ 채팅방 목록 로드 실패:', err);
    res.status(500).json({ message: '서버 오류' });
  }
};
// 🔹 메시지 불러오기
exports.getMessages = async (req, res) => {
  const { roomId, reader } = req.query;

  if (!roomId || !reader) {
    return res.status(400).json({ message: 'roomId와 reader 필수' });
  }

  try {
    console.log(`🔥 reader: ${reader}, roomId: ${roomId}`);

    // 상대방 메시지 읽음 처리
    await db.query(
      `UPDATE chat_messages SET is_read = 1 WHERE room_id = ? AND sender != ?`,
      [roomId, reader]
    );

    // 상대방 카운트 초기화
// ✅ 올바른 버전
const updateField = reader === 'worker' ? 'unread_count_worker' : 'unread_count_client';
    console.log(`👉 ${reader}가 읽음 → ${updateField} 0으로 초기화`);
    
    await db.query(
      `UPDATE chat_rooms SET ?? = 0 WHERE id = ?`,
      [updateField, roomId]
    );

    const [messages] = await db.query(
      `SELECT * FROM chat_messages WHERE room_id = ? ORDER BY created_at ASC`,
      [roomId]
    );

    res.json(messages);
  } catch (err) {
    console.error('❌ 메시지 불러오기 오류:', err);
    res.status(500).json({ message: '서버 오류' });
  }
};

// 🔹 메시지 전송
exports.sendMessage = async (req, res) => {
  const { roomId, sender, message } = req.body;

  if (!roomId || !sender || !message) {
    return res.status(400).json({ message: '필수 항목 누락' });
  }

  try {
    console.log(`🔥 sender: ${sender}, roomId: ${roomId}`);

    await db.query(
      `INSERT INTO chat_messages (room_id, sender, message) VALUES (?, ?, ?)`,
      [roomId, sender, message]
    );

    // 상대방 카운트 증가
    const incrementField = sender === 'user' ? 'unread_count_client' : 'unread_count_worker';
    console.log(`👉 ${sender}가 전송 → ${incrementField} +1`);

    await db.query(
      `UPDATE chat_rooms SET ${incrementField} = ${incrementField} + 1 WHERE id = ?`,
      [roomId]
    );

    // 최신 메시지, 시간 업데이트
    await db.query(
      `UPDATE chat_rooms SET last_message = ?, last_sent_at = NOW() WHERE id = ?`,
      [message, roomId]
    );

    res.status(200).json({ message: '메시지 전송 성공' });
  } catch (err) {
    console.error('❌ 메시지 전송 오류:', err);
    res.status(500).json({ message: '서버 오류' });
  }
};



// 🔹 채팅방 나가기
exports.leaveChatRoom = async (req, res) => {
  const { roomId } = req.params;

  if (!roomId) {
    return res.status(400).json({ message: 'roomId 필수' });
  }

  try {
    const [result] = await db.query(
      `UPDATE chat_rooms SET is_active = 0 WHERE id = ?`,
      [roomId]
    );

    if (result.affectedRows === 0) {
      return res.status(404).json({ message: '채팅방을 찾을 수 없습니다.' });
    }

    res.status(200).json({ message: '채팅방 나가기 성공' });
  } catch (err) {
    console.error('❌ 채팅방 나가기 오류:', err);
    res.status(500).json({ message: '서버 오류' });
  }
};

// 🔹 채팅방 상세 (공고 요약)
exports.getChatDetail = async (req, res) => {
  const { roomId } = req.params;

  if (!roomId) return res.status(400).json({ message: 'roomId 필수' });

  try {
    const [rows] = await db.query(
      `SELECT j.id, j.title, j.pay, j.created_at, cr.user_phone, cr.client_phone, u.name AS user_name, c.company_name AS client_company_name
      FROM chat_rooms cr
      JOIN jobs j ON cr.job_id = j.id
      JOIN users u ON cr.user_phone = u.phone
      JOIN clients c ON cr.client_phone = c.phone
      WHERE cr.id = ?` ,
      [roomId]
    );

    if (rows.length === 0) return res.status(404).json({ message: '채팅방 없음' });

    res.json(rows[0]);
  } catch (err) {
    console.error('❌ 채팅방 상세 오류:', err);
    res.status(500).json({ message: '서버 오류' });
  }
};

// 🔹 채용 확정 처리
exports.confirmHire = async (req, res) => {
  const { roomId } = req.params;

  if (!roomId) return res.status(400).json({ message: 'roomId 필수' });

  try {
    // 1️⃣ chat_rooms 테이블에서 채용 확정 표시
    await db.query(
      `UPDATE chat_rooms SET is_confirmed = 1 WHERE id = ?`,
      [roomId]
    );

    // 2️⃣ 관련 공고 상태도 업데이트 (선택적으로 사용)
    const [jobRow] = await db.query(
      `SELECT job_id FROM chat_rooms WHERE id = ?`,
      [roomId]
    );

    if (jobRow.length > 0) {
      await db.query(
        `UPDATE jobs SET status = 'confirmed' WHERE id = ?`,
        [jobRow[0].job_id]
      );
    }

    res.status(200).json({ message: '채용 확정 완료' });

    // (선택) 소켓 알림 추가 시:
    // io.to(roomId).emit('confirmed', { message: '채용이 확정되었습니다.' });

  } catch (err) {
    console.error('❌ 채용 확정 오류:', err);
    res.status(500).json({ message: '서버 오류' });
  }
};

// 🔹 총 안읽은 메시지 수 조회
exports.getUnreadCount = async (req, res) => {
  const { userPhone, userType } = req.query;

  if (!userPhone || !userType) {
    return res.status(400).json({ message: 'userPhone과 userType 필요' });
  }

  try {
    let sql = '';
    let param = [userPhone];

    if (userType === 'worker') {
      sql = `SELECT SUM(unread_count_worker) AS total FROM chat_rooms WHERE user_phone = ? AND is_active = 1`;
    } else if (userType === 'client') {
      sql = `SELECT SUM(unread_count_client) AS total FROM chat_rooms WHERE client_phone = ? AND is_active = 1`;
    } else {
      return res.status(400).json({ message: 'userType은 worker 또는 client여야 합니다.' });
    }

    const [rows] = await db.query(sql, param);
    const count = rows[0].total || 0;
    res.json({ unreadCount: count });

  } catch (err) {
    console.error('❌ 총 안읽은 수 조회 실패:', err);
    res.status(500).json({ message: '서버 오류' });
  }
};
