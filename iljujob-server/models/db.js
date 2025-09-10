const mysql = require('mysql2/promise');

const db = mysql.createPool({
  host: 'localhost',
  user: 'root',
  password: '1234',
  database: 'iljujob',
  waitForConnections: true,
  connectionLimit: 10,
});

module.exports = db;
