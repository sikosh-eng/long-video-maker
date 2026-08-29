 import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LongVideoMaker());
}

class LongVideoMaker extends StatelessWidget {
  const LongVideoMaker({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Long Video Maker',
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ImagePicker picker = ImagePicker();

  List<XFile> images = [];

  String? voicePath;
  String? musicPath;

  String format = '9:16';
  String resolution = '1080p';
  int fps = 30;

  bool autoDuration = true;
  bool zoomEnabled = true;
  bool transitionsEnabled = true;

  double voiceVolume = 100;
  double musicVolume = 20;

  bool processing = false;
  double progress = 0;

  String status = 'Готово к работе';

  // ------------------------------------------------------------
  // IMAGE PICKER
  // ------------------------------------------------------------

  Future<void> pickImages() async {
    try {
      final result = await picker.pickMultiImage();

      if (result.isNotEmpty) {
        setState(() {
          images = result;
          status = 'Выбрано изображений: ${images.length}';
        });
      }
    } catch (e) {
      showError('Ошибка выбора изображений:\n$e');
    }
  }

  // ------------------------------------------------------------
  // AUDIO PICKER
  // ------------------------------------------------------------

  Future<void> pickVoice() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          voicePath = result.files.single.path;
          status = 'Озвучка выбрана';
        });
      }
    } catch (e) {
      showError('Ошибка выбора озвучки:\n$e');
    }
  }

  Future<void> pickMusic() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          musicPath = result.files.single.path;
          status = 'Музыка выбрана';
        });
      }
    } catch (e) {
      showError('Ошибка выбора музыки:\n$e');
    }
  }

  // ------------------------------------------------------------
  // VIDEO SIZE
  // ------------------------------------------------------------

  String getVideoSize() {
    int base;

    switch (resolution) {
      case '480p':
        base = 480;
        break;

      case '720p':
        base = 720;
        break;

      case '1440p':
        base = 1440;
        break;

      case '2160p':
        base = 2160;
        break;

      default:
        base = 1080;
    }

    if (format == '16:9') {
      return '${base}x${(base * 9 / 16).round()}';
    }

    if (format == '1:1') {
      return '${base}x$base';
    }

    return '${(base * 9 / 16).round()}x$base';
  }

  // ------------------------------------------------------------
  // AUDIO DURATION
  // ------------------------------------------------------------

  Future<double?> getAudioDuration(String path) async {
    try {
      final session = await FFmpegKit.execute(
        '-i "${escape(path)}" -f null -',
      );

      final output = await session.getOutput();

      if (output == null) {
        return null;
      }

      final regex = RegExp(
        r'Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)',
      );

      final match = regex.firstMatch(output);

      if (match == null) {
        return null;
      }

      final hours = double.parse(match.group(1)!);
      final minutes = double.parse(match.group(2)!);
      final seconds = double.parse(match.group(3)!);

      return hours * 3600 + minutes * 60 + seconds;
    } catch (_) {
      return null;
    }
  }

  String escape(String value) {
    return value.replaceAll('"', '\\"');
  }

  // ------------------------------------------------------------
  // CREATE VIDEO
  // ------------------------------------------------------------

  Future<void> createVideo() async {
    if (images.isEmpty) {
      showError('Добавь изображения.');
      return;
    }

    if (voicePath == null) {
      showError('Добавь озвучку.');
      return;
    }

    setState(() {
      processing = true;
      progress = 0.05;
      status = 'Анализируем озвучку...';
    });

    try {
      final duration = await getAudioDuration(voicePath!);

      if (duration == null || duration <= 0) {
        throw Exception(
          'Не удалось определить длительность озвучки.',
        );
      }

      final imageDuration =
          autoDuration ? duration / images.length : 5.0;

      setState(() {
        progress = 0.15;
        status =
            'Озвучка: ${duration.toStringAsFixed(1)} сек\n'
            'На картинку: ${imageDuration.toStringAsFixed(2)} сек';
      });

      final temp = await getTemporaryDirectory();

      final listFile = File(
        '${temp.path}/images.txt',
      );

      final outputFile = File(
        '${temp.path}/long_video_${DateTime.now().millisecondsSinceEpoch}.mp4',
      );

      final buffer = StringBuffer();

      for (final image in images) {
        final path = image.path;

        buffer.writeln(
          "file '${path.replaceAll("'", "'\\''")}'",
        );

        buffer.writeln(
          'duration ${imageDuration.toStringAsFixed(3)}',
        );
      }

      if (images.isNotEmpty) {
        final last = images.last.path;

        buffer.writeln(
          "file '${last.replaceAll("'", "'\\''")}'",
        );
      }

      await listFile.writeAsString(
        buffer.toString(),
      );

      setState(() {
        progress = 0.25;
        status = 'Создаём видеоряд...';
      });

      final size = getVideoSize();

      String videoFilter =
          'scale=$size:force_original_aspect_ratio=increase,'
          'crop=$size,'
          'format=yuv420p';

      // --------------------------------------------------------
      // ZOOM
      // --------------------------------------------------------

      if (zoomEnabled) {
        videoFilter =
            'scale=$size:force_original_aspect_ratio=increase,'
            'crop=$size,'
            'zoompan='
            'z=min(zoom+0.0008,1.08):'
            'x=iw/2-(iw/zoom/2):'
            'y=ih/2-(ih/zoom/2):'
            'd=1:'
            's=$size:'
            'fps=$fps,'
            'format=yuv420p';
      }

      // --------------------------------------------------------
      // AUDIO
      // --------------------------------------------------------

      String audioInput =
          '-i "${escape(voicePath!)}"';

      String audioFilter =
          'volume=${(voiceVolume / 100).toStringAsFixed(2)}';

      String extraAudio = '';

      if (musicPath != null) {
        extraAudio =
            '-stream_loop -1 '
            '-i "${escape(musicPath!)}"';

        audioFilter =
            '[1:a]volume=${(voiceVolume / 100).toStringAsFixed(2)}[voice];'
            '[2:a]volume=${(musicVolume / 100).toStringAsFixed(2)}[music];'
            '[voice][music]amix=inputs=2:duration=first[a]';
      }

      // --------------------------------------------------------
      // COMMAND
      // --------------------------------------------------------

      String command;

      if (musicPath != null) {
        command = [
          '-y',
          '-f concat',
          '-safe 0',
          '-i "${listFile.path}"',
          audioInput,
          extraAudio,
          '-vf "$videoFilter"',
          '-filter_complex "$audioFilter"',
          '-map 0:v',
          '-map "[a]"',
          '-r $fps',
          '-c:v libx264',
          '-preset veryfast',
          '-crf 23',
          '-c:a aac',
          '-b:a 192k',
          '-shortest',
          '-movflags +faststart',
          '"${outputFile.path}"',
        ].join(' ');
      } else {
        command = [
          '-y',
          '-f concat',
          '-safe 0',
          '-i "${listFile.path}"',
          audioInput,
          '-vf "$videoFilter"',
          '-af "$audioFilter"',
          '-r $fps',
          '-c:v libx264',
          '-preset veryfast',
          '-crf 23',
          '-c:a aac',
          '-b:a 192k',
          '-shortest',
          '-movflags +faststart',
          '"${outputFile.path}"',
        ].join(' ');
      }

      setState(() {
        progress = 0.30;
        status =
            'Рендеринг...\n'
            '$size • $fps FPS';
      });

      await FFmpegKit.executeAsync(
        command,
        (session) async {
          final returnCode =
              await session.getReturnCode();

          if (ReturnCode.isSuccess(returnCode)) {
            setState(() {
              processing = false;
              progress = 1.0;
              status =
                  '✅ Видео готово!\n\n'
                  'Размер: $size\n'
                  'FPS: $fps\n\n'
                  '${outputFile.path}';
            });

            showSuccess(
              'Видео успешно создано!\n\n'
              'Формат: $format\n'
              'Разрешение: $resolution\n'
              'FPS: $fps',
            );
          } else {
            final output =
                await session.getOutput();

            setState(() {
              processing = false;
              status = '❌ Ошибка FFmpeg';
            });

            showError(
              'Ошибка создания видео:\n\n$output',
            );
          }
        },
        (log) {
          debugPrint(log.getMessage());
        },
        (statistics) {
          final time = statistics.getTime();

          if (duration > 0) {
            final value =
                0.30 +
                ((time / 1000) / duration) * 0.65;

            if (mounted) {
              setState(() {
                progress =
                    value.clamp(0.30, 0.95);
              });
            }
          }
        },
      );
    } catch (e) {
      setState(() {
        processing = false;
        progress = 0;
        status = 'Ошибка';
      });

      showError('Ошибка:\n$e');
    }
  }

  // ------------------------------------------------------------
  // UI
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Long Video Maker',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 5),

              const Icon(
                Icons.movie_creation,
                size: 60,
              ),

              const SizedBox(height: 10),

              const Text(
                'AUTO VIDEO MAKER',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 20),

              // IMAGES

              ElevatedButton.icon(
                onPressed:
                    processing ? null : pickImages,
                icon: const Icon(
                  Icons.photo_library,
                ),
                label: Text(
                  images.isEmpty
                      ? 'Добавить изображения'
                      : 'Изображения: ${images.length}',
                ),
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(
                    vertical: 17,
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // VOICE

              ElevatedButton.icon(
                onPressed:
                    processing ? null : pickVoice,
                icon: const Icon(Icons.mic),
                label: Text(
                  voicePath == null
                      ? 'Добавить озвучку'
                      : 'Озвучка ✓',
                ),
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(
                    vertical: 17,
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // MUSIC

              ElevatedButton.icon(
                onPressed:
                    processing ? null : pickMusic,
                icon: const Icon(Icons.music_note),
                label: Text(
                  musicPath == null
                      ? 'Добавить музыку'
                      : 'Музыка ✓',
                ),
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(
                    vertical: 17,
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // SETTINGS

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '⚙️ Настройки видео',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 20),

                      const Text(
                        'Формат',
                        style: TextStyle(
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 8),

                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: '9:16',
                            label: Text('9:16'),
                          ),
                          ButtonSegment(
                            value: '16:9',
                            label: Text('16:9'),
                          ),
                          ButtonSegment(
                            value: '1:1',
                            label: Text('1:1'),
                          ),
                        ],
                        selected: {format},
                        onSelectionChanged:
                            processing
                                ? null
                                : (value) {
                                    setState(() {
                                      format =
                                          value.first;
                                    });
                                  },
                      ),

                      const SizedBox(height: 20),

                      const Text(
                        'Разрешение',
                        style: TextStyle(
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 8),

                      DropdownButtonFormField<String>(
                        value: resolution,
                        decoration:
                            const InputDecoration(
                          border:
                              OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: '480p',
                            child: Text('480p'),
                          ),
                          DropdownMenuItem(
                            value: '720p',
                            child: Text('720p HD'),
                          ),
                          DropdownMenuItem(
                            value: '1080p',
                            child: Text('1080p Full HD'),
                          ),
                          DropdownMenuItem(
                            value: '1440p',
                            child: Text('1440p 2K'),
                          ),
                          DropdownMenuItem(
                            value: '2160p',
                            child: Text('2160p 4K'),
                          ),
                        ],
                        onChanged:
                            processing
                                ? null
                                : (value) {
                                    if (value !=
                                        null) {
                                      setState(() {
                                        resolution =
                                            value;
                                      });
                                    }
                                  },
                      ),

                      const SizedBox(height: 20),

                      const Text(
                        'FPS',
                        style: TextStyle(
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 8),

                      DropdownButtonFormField<int>(
                        value: fps,
                        decoration:
                            const InputDecoration(
                          border:
                              OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 24,
                            child: Text('24 FPS'),
                          ),
                          DropdownMenuItem(
                            value: 25,
                            child: Text('25 FPS'),
                          ),
                          DropdownMenuItem(
                            value: 30,
                            child: Text('30 FPS'),
                          ),
                          DropdownMenuItem(
                            value: 50,
                            child: Text('50 FPS'),
                          ),
                          DropdownMenuItem(
                            value: 60,
                            child: Text('60 FPS'),
                          ),
                        ],
                        onChanged:
                            processing
                                ? null
                                : (value) {
                                    if (value !=
                                        null) {
                                      setState(() {
                                        fps = value;
                                      });
                                    }
                                  },
        
