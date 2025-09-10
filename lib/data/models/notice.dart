class Notice {
  final int id;
  final String title;
  final String content;
  final String writer; // 여기를 추가!
  final String createdAt;

  Notice({
    required this.id,
    required this.title,
    required this.content,
    required this.writer,
    required this.createdAt,
  });

  factory Notice.fromJson(Map<String, dynamic> json) {
    return Notice(
      id: json['id'],
      title: json['title'],
      content: json['content'],
      writer: json['writer'] ?? '운영자', // null이면 기본값
      createdAt: json['created_at'],
    );
  }
}
