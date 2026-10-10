package com.nwbn.huelock

import android.os.Bundle
import com.google.android.gms.games.PlayGamesSdk
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Play Games is optional: only start it once a real project id is set
        // in res/values/games-ids.xml (otherwise the SDK would refuse to run).
        if (getString(R.string.game_services_project_id).isNotBlank()) {
            PlayGamesSdk.initialize(this)
        }
    }
}
