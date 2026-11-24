package com.vela

import android.app.Application
import android.content.Context
import android.os.Build

import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngineGroup

class VelaApplication : Application() {
    companion object {
        private lateinit var instance: VelaApplication
        fun getAppContext(): Context = instance.applicationContext
    }

    lateinit var engineGroup: FlutterEngineGroup

    override fun onCreate() {
        super.onCreate()
        instance = this
        GlobalState.updateIsStopping(false)
        FlutterInjector.instance().flutterLoader().startInitialization(this)
        engineGroup = FlutterEngineGroup(this)
    }
}
