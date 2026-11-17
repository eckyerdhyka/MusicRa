package com.musicra.app

import com.ryanheise.audioservice.AudioServiceActivity

// AudioServiceActivity shares one Flutter engine with the playback service,
// so reopening the app reattaches to the music that kept playing.
class MainActivity : AudioServiceActivity()
