import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';

late AudioHandler _audioHandler;

Future<void> main() async {
  _audioHandler = await AudioService.init(
    builder: () => AudioPlayerHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.ryanheise.myapp.channel.audio',
      androidNotificationChannelName: 'Audio playback',
      androidNotificationOngoing: true,
    ),
  );
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audio Service Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: MainScreen(),
    );
  }
}

class MainScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio Service Demo'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Show media item title

            // Play/pause/stop buttons.
            StreamBuilder<bool>(
              stream: _audioHandler.playbackState.map((state) => state.playing).distinct(),
              builder: (context, snapshot) {
                final playing = snapshot.data ?? false;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    playing
                        ? _button(Icons.pause, _audioHandler.pause)
                        : _button(Icons.play_arrow, () async {
                            try {
                              _audioHandler.playMediaItem(MediaItem(
                                id: '/s3.amazonaws.com/scifri-episodes/scifri20181123-episode.mp3',
                                album: "Science Friday",
                                title: "A Salute To Head-Scratching Science",
                                artist: "Science Friday and WNYC Studios",
                                duration: const Duration(milliseconds: 5739820),
                                artUri: Uri.parse('https://media.wnyc.org/i/1400/1400/l/80/1/ScienceFriday_WNYCStudios_1400.jpg'),
                              ));
                            } on PlatformException catch (err) {
                              print(err);
                            } catch (err) {
                              print("playMediaItem ERROR");
                              print(err);
                            }
                            print("playMediaItem end");
                          }),
                    _button(Icons.stop, _audioHandler.stop),
                  ],
                );
              },
            ),
            // A seek bar.

            // Display the processing state.
            StreamBuilder<AudioProcessingState>(
              stream: _audioHandler.playbackState.map((state) => state.processingState).distinct(),
              builder: (context, snapshot) {
                final processingState = snapshot.data ?? AudioProcessingState.idle;
                return Text("Processing state: ${describeEnum(processingState)}");
              },
            ),
          ],
        ),
      ),
    );
  }

  /// A stream reporting the combined state of the current media item and its
  /// current position.
  Stream<MediaState> get _mediaStateStream => Rx.combineLatest2<MediaItem?, Duration, MediaState>(_audioHandler.mediaItem, AudioService.position, (mediaItem, position) => MediaState(mediaItem, position));

  IconButton _button(IconData iconData, dynamic onPressed) => IconButton(
        icon: Icon(iconData),
        iconSize: 64.0,
        onPressed: () => onPressed(),
      );
}

class MediaState {
  final MediaItem? mediaItem;
  final Duration position;

  MediaState(this.mediaItem, this.position);
}

/// An [AudioHandler] for playing a single item.
class AudioPlayerHandler extends BaseAudioHandler {
  final AudioPlayer _player = AudioPlayer();

  AudioPlayerHandler() {
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);
  }

  @override
  Future<void> onTaskRemoved() async {
    await stop();
    super.onTaskRemoved();
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: <MediaControl>[
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
      ],
      systemActions: const <MediaAction>{},
      androidCompactActionIndices: const <int>[0, 1],
      processingState: const <ProcessingState, AudioProcessingState>{
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    );
  }

  @override
  Future<void> playMediaItem(MediaItem mediaItem) async {
    this.mediaItem.add(mediaItem);

    /// if the property preload is [true] on ios, ios while display the play button icon and then pause button, weird
    await _player.setUrl(mediaItem.id, preload: false);
    await play();
  }

  @override
  Future<void> updateMediaItem(MediaItem mediaItem) async {
    this.mediaItem.add(mediaItem);
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> play() async {
    await _player.seek(null);
    await _player.play();
  }

  @override
  Future<void> stop() async {
    await _player.pause();
    await _player.stop();
  }

  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    switch (button) {
      case MediaButton.media:
        if (playbackState.value.playing == true) {
          await pause();
        } else {
          await play();
        }
        break;
      case MediaButton.next:
        await skipToNext();
        break;
      case MediaButton.previous:
        await skipToPrevious();
        break;
    }
  }
}
