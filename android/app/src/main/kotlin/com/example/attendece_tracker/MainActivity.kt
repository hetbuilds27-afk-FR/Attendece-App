package com.example.attendece_tracker

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.annotation.NonNull
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private val safChannelName = "attendance_tracker/saf"
    private val openTreeRequestCode = 4201
    private var pendingPickResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "attendance_tracker/widget")
            .setMethodCallHandler { call, result ->
                if (call.method == "refresh") {
                    AttendanceWidgetProvider.refresh(this)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, safChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openTree" -> {
                        pendingPickResult = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                        intent.addFlags(
                            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                        )
                        startActivityForResult(intent, openTreeRequestCode)
                    }
                    "hasPermission" -> {
                        val treeUri = Uri.parse(call.argument<String>("treeUri"))
                        val granted = contentResolver.persistedUriPermissions.any {
                            it.uri == treeUri && it.isReadPermission && it.isWritePermission
                        }
                        result.success(granted)
                    }
                    "writeFile" -> {
                        try {
                            val treeUri = Uri.parse(call.argument<String>("treeUri"))
                            val fileName = call.argument<String>("fileName")!!
                            val content = call.argument<String>("content")!!
                            val tree = DocumentFile.fromTreeUri(this, treeUri)
                            var target = tree?.findFile(fileName)
                            if (target == null) {
                                target = tree?.createFile("application/json", fileName)
                            }
                            if (target == null) {
                                result.success(false)
                            } else {
                                contentResolver.openOutputStream(target.uri, "wt")?.use { out ->
                                    out.write(content.toByteArray(Charsets.UTF_8))
                                }
                                result.success(true)
                            }
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "readFile" -> {
                        try {
                            val treeUri = Uri.parse(call.argument<String>("treeUri"))
                            val fileName = call.argument<String>("fileName")!!
                            val tree = DocumentFile.fromTreeUri(this, treeUri)
                            val target = tree?.findFile(fileName)
                            if (target == null) {
                                result.success(null)
                            } else {
                                val buffer = ByteArrayOutputStream()
                                contentResolver.openInputStream(target.uri)?.use { input ->
                                    input.copyTo(buffer)
                                }
                                result.success(buffer.toString("UTF-8"))
                            }
                        } catch (e: Exception) {
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == openTreeRequestCode) {
            val result = pendingPickResult
            pendingPickResult = null
            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                val treeUri = data.data!!
                contentResolver.takePersistableUriPermission(
                    treeUri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                )
                result?.success(treeUri.toString())
            } else {
                result?.success(null)
            }
        }
    }
}