package com.example.rachan

import android.Manifest
import android.content.ContentResolver
import android.content.ContentUris
import android.content.pm.PackageManager
import android.database.Cursor
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

// audio_service (used by just_audio_background) requires the Activity to
// extend AudioServiceActivity instead of FlutterActivity so it can bind to
// the background audio service correctly.
class MainActivity : AudioServiceActivity() {
    private val CHANNEL = "com.example.harmoniq/local_music"
    private val PERMISSION_REQUEST_CODE = 1001
    private val pendingPermissionResults = mutableListOf<MethodChannel.Result>()
    private val pendingScanResults = mutableSetOf<MethodChannel.Result>()
    private val scanExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var musicChannel: MethodChannel? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        musicChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        musicChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "checkPermission" -> {
                    result.success(checkMusicPermission())
                }
                "checkAllPermissions" -> {
                    result.success(checkAllPermissions())
                }
                "requestPermission", "requestAllPermissions" -> {
                    pendingPermissionResults.add(result)
                    if (pendingPermissionResults.size == 1) requestRequiredPermissions()
                }
                "fetchLocalSongs" -> {
                    if (checkMusicPermission()) {
                        fetchLocalSongsAsync(result)
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
            completePermissionRequests(true)
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
            completePermissionRequests(storageGranted)
        }
    }

    private fun completePermissionRequests(granted: Boolean) {
        val results = pendingPermissionResults.toList()
        pendingPermissionResults.clear()
        results.forEach { it.success(granted) }
    }

    private fun fetchLocalSongsAsync(result: MethodChannel.Result) {
        // Query and cursor traversal can be slow for large libraries. Use the
        // application resolver so the worker does not need a live Activity.
        val resolver = applicationContext.contentResolver
        pendingScanResults.add(result)
        scanExecutor.execute {
            try {
                val songs = fetchLocalSongs(resolver)
                mainHandler.post {
                    if (pendingScanResults.remove(result)) result.success(songs)
                }
            } catch (error: Exception) {
                mainHandler.post {
                    if (pendingScanResults.remove(result)) {
                        val code = if (error is SecurityException) "PERMISSION_DENIED" else "SCAN_FAILED"
                        result.error(code, error.message ?: "Unable to scan local music", null)
                    }
                }
            }
        }
    }

    override fun onDestroy() {
        musicChannel?.setMethodCallHandler(null)
        musicChannel = null
        pendingScanResults.forEach {
            it.error("ACTIVITY_DESTROYED", "Local music scan interrupted", null)
        }
        pendingScanResults.clear()
        completePermissionRequests(false)
        scanExecutor.shutdownNow()
        super.onDestroy()
    }

    private fun fetchLocalSongs(resolver: ContentResolver): List<Map<String, Any>> {
        val songsList = mutableListOf<Map<String, Any>>()

        val uri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION
        )
        val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0"
        val sortOrder = "${MediaStore.Audio.Media.TITLE} ASC"

        val cursor: Cursor? = resolver.query(uri, projection, selection, null, sortOrder)
        cursor?.use {
            val idCol       = it.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val titleCol    = it.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artistCol   = it.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val albumCol    = it.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val durationCol = it.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)

            while (!Thread.currentThread().isInterrupted && it.moveToNext()) {
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
