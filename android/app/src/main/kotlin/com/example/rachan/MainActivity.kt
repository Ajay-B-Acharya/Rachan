package com.example.rachan

import android.Manifest
import android.content.ContentUris
import android.content.pm.PackageManager
import android.database.Cursor
import android.os.Build
import android.provider.MediaStore
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// audio_service (used by just_audio_background) requires the Activity to
// extend AudioServiceActivity instead of FlutterActivity so it can bind to
// the background audio service correctly.
class MainActivity : AudioServiceActivity() {
    private val CHANNEL = "com.example.harmoniq/local_music"
    private val PERMISSION_REQUEST_CODE = 1001
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkPermission" -> {
                    result.success(checkMusicPermission())
                }
                "checkAllPermissions" -> {
                    result.success(checkAllPermissions())
                }
                "requestPermission", "requestAllPermissions" -> {
                    pendingResult = result
                    requestRequiredPermissions()
                }
                "fetchLocalSongs" -> {
                    if (checkMusicPermission()) {
                        result.success(fetchLocalSongs())
                    } else {
                        result.error("PERMISSION_DENIED", "Storage/Media permission is not granted", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun getStoragePermission(): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_AUDIO
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }
    }

    private fun checkMusicPermission(): Boolean {
        val permission = getStoragePermission()
        return ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED
    }

    private fun checkNotificationPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(
                this, Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    private fun checkAllPermissions(): Map<String, Boolean> {
        val storage = checkMusicPermission()
        val notification = checkNotificationPermission()
        return mapOf(
            "storage" to storage,
            "notification" to notification,
            "allGranted" to (storage && notification)
        )
    }

    private fun requestRequiredPermissions() {
        val permissionsToRequest = mutableListOf<String>()
        if (!checkMusicPermission()) {
            permissionsToRequest.add(getStoragePermission())
        }
        if (!checkNotificationPermission() && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            permissionsToRequest.add(Manifest.permission.POST_NOTIFICATIONS)
        }

        if (permissionsToRequest.isEmpty()) {
            pendingResult?.success(true)
            pendingResult = null
        } else {
            ActivityCompat.requestPermissions(
                this, permissionsToRequest.toTypedArray(), PERMISSION_REQUEST_CODE
            )
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST_CODE) {
            val storageGranted = checkMusicPermission()
            pendingResult?.success(storageGranted)
            pendingResult = null
        }
    }

    private fun fetchLocalSongs(): List<Map<String, Any>> {
        val songsList = mutableListOf<Map<String, Any>>()

        val uri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.DATA
        )
        val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0"
        val sortOrder = "${MediaStore.Audio.Media.TITLE} ASC"

        val cursor: Cursor? = contentResolver.query(uri, projection, selection, null, sortOrder)
        cursor?.use {
            val idCol       = it.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val titleCol    = it.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artistCol   = it.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val albumCol    = it.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val durationCol = it.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)

            while (it.moveToNext()) {
                val id       = it.getLong(idCol)
                val title    = it.getString(titleCol)    ?: "Unknown Title"
                val artist   = it.getString(artistCol)   ?: "Unknown Artist"
                val album    = it.getString(albumCol)    ?: "Unknown Album"
                val duration = it.getLong(durationCol)

                val contentUri = ContentUris.withAppendedId(
                    MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id
                ).toString()

                songsList.add(
                    mapOf(
                        "id"       to id.toInt(),
                        "title"    to title,
                        "artist"   to artist,
                        "album"    to album,
                        "duration" to duration,
                        "path"     to contentUri
                    )
                )
            }
        }
        return songsList
    }
}
