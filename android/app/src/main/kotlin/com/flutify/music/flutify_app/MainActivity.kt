package com.flutify.music.flutify_app

import com.ryanheise.audioservice.AudioServiceActivity

// audio_service 要求：Activity 与后台媒体服务共用同一个 Flutter 引擎（通知栏 / 锁屏控件）
class MainActivity : AudioServiceActivity()
