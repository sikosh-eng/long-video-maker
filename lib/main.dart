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
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
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
  final ImagePicker _imagePicker = ImagePicker();

  List<XFile> images = [];
  String? audioPath;

  bool isProcessing = false;
  double progress = 0;

  String status = 'Готово к работе';

  Future<void> selectImages() async {
    try {
      final selected = await _imagePicker.pickMultiImage();

      if (selected.isNotEmpty) {
        setState(() {
          images = selected;
          status = 'Выбрано изображений: ${images.length}';
        });
      }
    } catch (e) {
      showError('Не удалось выбрать изображения:\n$e');
    }
  }

  Future<void> selectAudio() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );

      if (result != null &&
          result.files.single.path != null) {
        setState(() {
          audioPath = result.files.single.path!;
          status = 'Озвучка выбрана';
        });
      }
    } catch (e) {
      showError('Не удалось выбрать озвучку:\n$e');
    }
  }

  Future<double?> getAudioDuration(String path) async {
    try {
      final session = await FFmpegKit.execute(
        '-i "${escapePath(path)}" -f null -'
      );

      final output = await session.getOutput();

      if (output == null) return null;

      final regex = RegExp(
        r'Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)',
      );

      final match = regex.firstMatch(output);

      if (match == null) return null;

      final hours = double.parse(match.group(1)!);
      final minutes = double.parse(match.group(2)!);
      final seconds = double.parse(match.group(3)!);

      return hours * 3600 + minutes * 60 + seconds;
    } catch (_) {
      return null;
    }
  }

  String escapePath(String path) {
    return path.replaceAll('"', '\\"');
  }

  Future<void> createVideo() async {
    if (images.isEmpty) {
      showError('Сначала добавь изображения.');
      return;
    }

    if (audioPath == null) {
      showError('Сначала добавь озвучку.');
      return;
    }

    setState(() {
      isProcessing = true;
      progress = 0.05;
      status = 'Определяем длительность озвучки...';
    });

    try {
      final audioDuration = await getAudioDuration(audioPath!);

      if (audioDuration == null || audioDuration <= 0) {
        throw Exception(
          'Не удалось определить длительность озвучки.',
        );
      }

      final secondsPerImage =
          audioDuration / images.length;

      setState(() {
        progress = 0.15;
        status =
            'Длительность: ${audioDuration.toStringAsFixed(1)} сек\n'
            'На одну картинку: ${secondsPerImage.toStringAsFixed(2)} сек';
      });

      final tempDir = await getTemporaryDirectory();

      final listFile = File(
        '${tempDir.path}/images.txt',
      );

      final outputFile = File(
        '${tempDir.path}/long_video.mp4',
      );

      if (outputFile.existsSync()) {
        await outputFile.delete();
      }

      final buffer = StringBuffer();

      for (final image in images) {
        final path = image.path;

        buffer.writeln(
          "file '${path.replaceAll("'", "'\\''")}'",
        );

        buffer.writeln(
          'duration ${secondsPerImage.toStringAsFixed(3)}',
        );
      }

      // Последнее изображение повторяем,
      // чтобы FFmpeg корректно завершил concat.
      if (images.isNotEmpty) {
        final last = images.last.path;

        buffer.writeln(
          "file '${last.replaceAll("'", "'\\''")}'",
        );
      }

      await listFile.writeAsString(buffer.toString());

      setState(() {
        progress = 0.25;
        status = 'Создаём видеоряд...';
      });

      final command = [
        '-y',
        '-f concat',
        '-safe 0',
        '-i "${listFile.path}"',
        '-i "${escapePath(audioPath!)}"',
        '-vf "scale=1080:1920:force_original_aspect_ratio=increase,'
            'crop=1080:1920,'
            'format=yuv420p"',
        '-r 30',
        '-c:v libx264',
        '-preset veryfast',
        '-crf 23',
        '-c:a aac',
        '-b:a 192k',
        '-shortest',
        '-movflags +faststart',
        '"${outputFile.path}"',
      ].join(' ');

      final session = await FFmpegKit.executeAsync(
        command,
        (completedSession) async {
          final returnCode =
              await completedSession.getReturnCode();

          if (ReturnCode.isSuccess(returnCode)) {
            setState(() {
              isProcessing = false;
              progress = 1.0;
              status =
                  '✅ Видео готово!\n${outputFile.path}';
            });

            showSuccess(
              'Видео успешно создано!\n\n'
              'Файл находится во временной папке приложения.',
            );
          } else {
            final logs =
                await completedSession.getOutput();

            setState(() {
              isProcessing = false;
              status = '❌ Ошибка FFmpeg';
            });

            showError(
              'FFmpeg завершился с ошибкой.\n\n$logs',
            );
          }
        },
        (log) {
          debugPrint(log.getMessage());
        },
        (statistics) {
          final time = statistics.getTime();

          if (audioDuration > 0) {
            final calculated =
                0.25 +
                ((time / 1000) / audioDuration) * 0.70;

            setState(() {
              progress =
                  calculated.clamp(0.25, 0.95);
            });
          }
        },
      );

      setState(() {
        progress = 0.30;
        status = 'Рендеринг видео...';
      });

      await session;
    } catch (e) {
      setState(() {
        isProcessing = false;
        progress = 0;
        status = 'Ошибка';
      });

      showError('Ошибка:\n$e');
    }
  }

  void showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void showSuccess(String message) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Готово 🎉'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

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
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),

              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius:
                      BorderRadius.circular(20),
                  color: Colors.white.withOpacity(0.06),
                ),
                child: const Column(
                  children: [
                    Icon(
                      Icons.movie_creation_outlined,
                      size: 60,
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Автоматический монтаж',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Картинки + озвучка → готовое видео',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              ElevatedButton.icon(
                onPressed:
                    isProcessing ? null : selectImages,
                icon: const Icon(Icons.photo_library),
                label: Text(
                  images.isEmpty
                      ? 'Добавить картинки'
                      : 'Картинки: ${images.length}',
                ),
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(
                    vertical: 17,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              ElevatedButton.icon(
                onPressed:
                    isProcessing ? null : selectAudio,
                icon: const Icon(Icons.mic),
                label: Text(
                  audioPath == null
                      ? 'Добавить озвучку'
                      : 'Озвучка выбрана ✓',
                ),
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(
                    vertical: 17,
                  ),
                ),
              ),

              const SizedBox(height: 20),

              Card(
                child: Padding(
                  padding:
                      const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Text(
                        'Настройки',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 15),
                      const Row(
                        mainAxisAlignment:
                            MainAxisAlignment
                                .spaceBetween,
                        children: [
                          Text('Формат'),
                          Text(
                            '9:16',
                            style: TextStyle(
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Row(
                        mainAxisAlignment:
                            MainAxisAlignment
                                .spaceBetween,
                        children: [
                          Text('Разрешение'),
                          Text(
                            '1080 × 1920',
                            style: TextStyle(
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Row(
                        mainAxisAlignment:
                            MainAxisAlignment
                                .spaceBetween,
                        children: [
                          Text('FPS'),
                          Text(
                            '30',
                            style: TextStyle(
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              if (isProcessing) ...[
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  borderRadius:
                      BorderRadius.circular(10),
                ),
                const SizedBox(height: 10),
                Text(
                  '${(progress * 100).toInt()}%',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
              ],

              Text(
                status,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                ),
              ),

              const SizedBox(height: 20),

              FilledButton.icon(
                onPressed:
                    isProcessing
                        ? null
                        : createVideo,
                icon: const Icon(
                  Icons.play_arrow,
                ),
                label: const Text(
                  'СОЗДАТЬ ВИДЕО',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(
                    vertical: 18,
                  ),
                ),
              ),

              const SizedBox(height: 30),

              const Text(
                'Первая версия\n\n'
                '• Автоматически распределяет изображения\n'
                '• Подгоняет их под длину озвучки\n'
                '• Создаёт вертикальное видео 9:16\n'
                '• Добавляет аудио\n'
                '• Экспортирует MP4\n\n'
                'Следующая версия сможет добавить '
                'субтитры, музыку, переходы и Zoom.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
