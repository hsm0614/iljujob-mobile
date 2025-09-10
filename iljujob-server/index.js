const os = require('os');
const express = require('express');
const cors = require('cors');
const http = require('http');
const path = require('path');
const fs = require('fs');

const bodyParser = require('body-parser');
const db = require('./models/db');
const cron = require('node-cron');
const { Server } = require('socket.io');  
const app = express();
const PORT = 3000;

require('dotenv').config();
const server = http.createServer(app);  
const io = new Server(server, {
  cors: {
    origin: '*',
  }
});

// 백엔드 CORS 설정
app.use(cors({
  origin: '*',
  methods: ['GET', 'POST', 'PUT', 'DELETE'],
}));

app.use(express.json());
app.use(bodyParser.urlencoded({ extended: true }));
// uploads/profile 디렉토리 자동 생성
const uploadDir = path.join(__dirname, 'uploads/profile');
if (!fs.existsSync(uploadDir)) {
  fs.mkdirSync(uploadDir, { recursive: true });
}

// 로컬 IP 주소 자동 설정
const getLocalIP = () => {
  const interfaces = os.networkInterfaces();
  let localIP = 'localhost';  // 기본값을 localhost로 설정

  for (let interfaceName in interfaces) {
    const iface = interfaces[interfaceName];
    for (let i = 0; i < iface.length; i++) {
      const address = iface[i];
      // IPv4 주소만 필터링
      if (address.family === 'IPv4' && !address.internal) {
        localIP = address.address;
        break;
      }
    }
  }
  return localIP;
};

const localIP = getLocalIP();
const baseUrl = `http://${localIP}:${PORT}`;  // 동적으로 IP 설정

console.log(`Server is running on ${baseUrl}`);

// 라우트 연결
const clientRoutes = require('./routes/client');
const workerRoutes = require('./routes/worker');
const jobRoutes = require('./routes/job');
const chatRoutes = require('./routes/chat');
const applyRoutes = require('./routes/apply');
const bookmarkRoutes = require('./routes/bookmark');
const inquiryRouter = require('./routes/inquiry');
const reportRoutes = require('./routes/report');

app.use('/api/chat', chatRoutes); 
app.use('/api/client', clientRoutes);
app.use('/api/worker', workerRoutes);
app.use('/api/job', jobRoutes);
app.use('/api', (req, res, next) => {
  console.log(`요청 경로: ${req.method} ${req.originalUrl}`);
  next();
}, applyRoutes);
app.use('/api/bookmark', bookmarkRoutes);
app.use('/api/inquiry', inquiryRouter);
app.use('/api/report', reportRoutes);
app.use('/uploads', express.static('uploads'));
app.use('/api/apply', applyRoutes);





cron.schedule('*/5 * * * *', async () => {
  console.log('🛠️ 5분마다 자동 공고 마감 작업 실행');

  const sql = `
    UPDATE jobs
    SET status = 'closed'
    WHERE status = 'active'
      AND created_at <= NOW() - INTERVAL 24 HOUR
      AND id IS NOT NULL;
  `;

  try {
    const [result] = await db.query(sql);
    console.log(`✅ 자동 마감된 공고 수: ${result.affectedRows}`);
  } catch (err) {
    console.error('❌ 공고 자동 마감 실패:', err);
  }
});

io.on('connection', (socket) => {
  console.log('✅ 새로운 클라이언트 연결됨');

  socket.on('join_room', (data) => {
    const { roomId } = data;
    socket.join(roomId);
    console.log(`🚪 방 ${roomId} 입장`);
  });

  socket.on('send_message', async (data) => {
    const { roomId, sender, message } = data;
    console.log(`📩 ${roomId}로부터 메시지: ${message}`);

    try {
      // DB에 메시지 저장
      await db.query(
        `INSERT INTO chat_messages (room_id, sender, message) VALUES (?, ?, ?)`,
        [roomId, sender, message]
      );

      // unread 카운트 증가
      const incrementField = sender === 'user' ? 'unread_count_client' : 'unread_count_worker';
      await db.query(
        `UPDATE chat_rooms SET ${incrementField} = ${incrementField} + 1 WHERE id = ?`,
        [roomId]
      );

      // last_message, last_sent_at 업데이트
      await db.query(
        `UPDATE chat_rooms SET last_message = ?, last_sent_at = NOW() WHERE id = ?`,
        [message, roomId]
      );

      // 방의 사용자들에게 메시지 전달
      io.to(roomId).emit('receive_message', { sender, message });

    } catch (err) {
      console.error('❌ WebSocket 메시지 처리 오류:', err);
      socket.emit('error_message', { message: '서버 오류' });
    }
  });

  socket.on('disconnect', () => {
    console.log('❌ 클라이언트 연결 끊김');
  });
});

// 서버 시작
server.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 서버 실행 중: ${baseUrl}`);
});
