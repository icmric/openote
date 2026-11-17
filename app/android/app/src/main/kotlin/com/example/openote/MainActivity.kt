package com.example.openote

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The phone's way into a folder the person chooses (Google Drive's, say) through
 * Android's own folder picker: list, read and write by document id, with no
 * Google account or sign-in inside the app. The picker grants access to ONE folder
 * and its contents, once, and the grant is kept.
 *
 * Everything that touches the provider runs off the main thread: a Drive folder
 * answers over the network.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "org.openote/saf"
    private val pickRequest = 4711
    private var pendingPick: MethodChannel.Result? = null

    // "Save a copy": the system's own Save-as screen (which can save to Google
    // Drive as well as to the phone), because the desktop's save dialog does not
    // exist here.
    private val saveRequest = 4712
    private var pendingSave: MethodChannel.Result? = null
    private var pendingSaveBytes: ByteArray? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickTree" -> {
                        pendingPick = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                            addFlags(
                                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
                            )
                        }
                        startActivityForResult(intent, pickRequest)
                    }
                    "saveFile" -> {
                        if (pendingSave != null) {
                            result.error("busy", "a save is already open", null)
                        } else {
                            @Suppress("UNCHECKED_CAST")
                            val a = call.arguments as Map<String, Any?>
                            pendingSave = result
                            pendingSaveBytes = a["bytes"] as ByteArray
                            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = (a["mime"] as String?) ?: "application/octet-stream"
                                putExtra(Intent.EXTRA_TITLE, a["name"] as String)
                            }
                            startActivityForResult(intent, saveRequest)
                        }
                    }
                    "list", "read", "write", "mkdir" -> background(call.method, call.arguments, result)
                    else -> result.notImplemented()
                }
            }
    }

    @Suppress("UNCHECKED_CAST")
    private fun background(method: String, args: Any?, result: MethodChannel.Result) {
        val a = args as Map<String, Any?>
        Thread {
            try {
                val out: Any? = when (method) {
                    "list" -> list(a["tree"] as String, a["doc"] as String?)
                    "read" -> read(a["tree"] as String, a["doc"] as String)
                    "write" -> write(
                        a["tree"] as String,
                        a["parent"] as String?,
                        a["name"] as String,
                        a["bytes"] as ByteArray
                    )
                    "mkdir" -> mkdir(
                        a["tree"] as String,
                        a["parent"] as String?,
                        a["name"] as String
                    )
                    else -> null
                }
                runOnUiThread { result.success(out) }
            } catch (e: Exception) {
                runOnUiThread { result.error("saf", e.toString(), null) }
            }
        }.start()
    }

    private fun treeUri(tree: String): Uri = Uri.parse(tree)

    private fun list(tree: String, doc: String?): List<Map<String, Any?>> {
        val t = treeUri(tree)
        val id = doc ?: DocumentsContract.getTreeDocumentId(t)
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(t, id)
        val cols = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED
        )
        val out = ArrayList<Map<String, Any?>>()
        contentResolver.query(children, cols, null, null, null)?.use { c ->
            while (c.moveToNext()) {
                out.add(
                    mapOf(
                        "id" to c.getString(0),
                        "name" to c.getString(1),
                        "dir" to (c.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR),
                        "size" to (if (c.isNull(3)) -1L else c.getLong(3)),
                        "modified" to (if (c.isNull(4)) -1L else c.getLong(4))
                    )
                )
            }
        }
        return out
    }

    private fun read(tree: String, doc: String): ByteArray {
        val uri = DocumentsContract.buildDocumentUriUsingTree(treeUri(tree), doc)
        contentResolver.openInputStream(uri).use { return it!!.readBytes() }
    }

    /** A folder called [name] in [parent]: the one that is there, or a new one. */
    private fun mkdir(tree: String, parent: String?, name: String): String {
        val t = treeUri(tree)
        val parentId = parent ?: DocumentsContract.getTreeDocumentId(t)
        val existing = list(tree, parentId).firstOrNull { it["name"] == name && it["dir"] == true }
        if (existing != null) return existing["id"] as String
        val parentUri = DocumentsContract.buildDocumentUriUsingTree(t, parentId)
        val uri = DocumentsContract.createDocument(
            contentResolver, parentUri, DocumentsContract.Document.MIME_TYPE_DIR, name
        ) ?: throw IllegalStateException("could not create folder $name")
        return DocumentsContract.getDocumentId(uri)
    }

    /** Create the file, or replace its whole content if it is already there. */
    private fun write(tree: String, parent: String?, name: String, bytes: ByteArray): String {
        val t = treeUri(tree)
        val parentId = parent ?: DocumentsContract.getTreeDocumentId(t)
        val existing = list(tree, parentId).firstOrNull { it["name"] == name && it["dir"] == false }
        val docId: String
        val uri: Uri
        if (existing != null) {
            docId = existing["id"] as String
            uri = DocumentsContract.buildDocumentUriUsingTree(t, docId)
        } else {
            val parentUri = DocumentsContract.buildDocumentUriUsingTree(t, parentId)
            uri = DocumentsContract.createDocument(
                contentResolver, parentUri, "application/octet-stream", name
            ) ?: throw IllegalStateException("could not create $name")
            docId = DocumentsContract.getDocumentId(uri)
        }
        // "wt": write, truncating, so a shorter file does not keep an old tail.
        contentResolver.openOutputStream(uri, "wt").use { it!!.write(bytes) }
        return docId
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == pickRequest) {
            val result = pendingPick
            pendingPick = null
            val uri = data?.data
            if (resultCode == Activity.RESULT_OK && uri != null) {
                contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                )
                result?.success(uri.toString())
            } else {
                result?.success(null)
            }
            return
        }
        if (requestCode == saveRequest) {
            val result = pendingSave
            val bytes = pendingSaveBytes
            pendingSave = null
            pendingSaveBytes = null
            val uri = data?.data
            if (resultCode == Activity.RESULT_OK && uri != null && bytes != null) {
                Thread {
                    try {
                        contentResolver.openOutputStream(uri, "wt").use { it!!.write(bytes) }
                        runOnUiThread { result?.success(uri.toString()) }
                    } catch (e: Exception) {
                        runOnUiThread { result?.error("save", e.toString(), null) }
                    }
                }.start()
            } else {
                result?.success(null)
            }
            return
        }
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }
}
