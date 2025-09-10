import 'package:flutter/material.dart';

class FullImageGalleryScreen extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;

  const FullImageGalleryScreen({
    Key? key,
    required this.urls,
    this.initialIndex = 0,
  }) : super(key: key);

  @override
  State<FullImageGalleryScreen> createState() => _FullImageGalleryScreenState();
}

class _FullImageGalleryScreenState extends State<FullImageGalleryScreen> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.urls;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1}/${urls.length}'),
      ),
      body: PageView.builder(
        controller: _controller,
        onPageChanged: (i) => setState(() => _index = i),
        itemCount: urls.length,
        itemBuilder: (_, i) => Center(
          child: InteractiveViewer(
            minScale: 0.8,
            maxScale: 4.0,
            child: Image.network(urls[i], fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}