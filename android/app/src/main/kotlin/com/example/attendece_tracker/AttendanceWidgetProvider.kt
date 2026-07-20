package com.example.attendece_tracker

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import kotlin.math.roundToInt

class AttendanceWidgetProvider : AppWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_MARK_ATTENDANCE) {
            val subjectIndex = intent.getIntExtra(EXTRA_SUBJECT_INDEX, -1)
            val present = intent.getBooleanExtra(EXTRA_PRESENT, true)
            AttendanceWidgetData.markAttendance(context, subjectIndex, present)
            refresh(context)
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        updateWidgets(context, appWidgetManager, appWidgetIds)
    }

    companion object {
        private const val ACTION_MARK_ATTENDANCE = "com.example.attendece_tracker.MARK_ATTENDANCE"
        private const val EXTRA_SUBJECT_INDEX = "subject_index"
        private const val EXTRA_PRESENT = "present"

        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, AttendanceWidgetProvider::class.java))
            updateWidgets(context, manager, ids)
        }

        private fun updateWidgets(
            context: Context,
            manager: AppWidgetManager,
            ids: IntArray
        ) {
            val data = AttendanceWidgetData.load(context)
            ids.forEach { id ->
                manager.updateAppWidget(id, buildViews(context, data))
            }
        }

        private fun buildViews(context: Context, data: AttendanceWidgetData): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.attendance_widget)
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

            views.setTextViewText(R.id.widget_percentage, "${data.overallPercent.roundToInt()}%")
            views.setTextViewText(R.id.widget_summary, "${data.attended}/${data.total} classes")

            val rows = listOf(
                WidgetRowViews(R.id.subject_row_1, R.id.subject_name_1, R.id.subject_stats_1, R.id.subject_present_1, R.id.subject_absent_1),
                WidgetRowViews(R.id.subject_row_2, R.id.subject_name_2, R.id.subject_stats_2, R.id.subject_present_2, R.id.subject_absent_2),
                WidgetRowViews(R.id.subject_row_3, R.id.subject_name_3, R.id.subject_stats_3, R.id.subject_present_3, R.id.subject_absent_3),
                WidgetRowViews(R.id.subject_row_4, R.id.subject_name_4, R.id.subject_stats_4, R.id.subject_present_4, R.id.subject_absent_4),
            )

            if (data.subjects.isEmpty()) {
                views.setViewVisibility(R.id.empty_message, View.VISIBLE)
                rows.forEach { views.setViewVisibility(it.rowId, View.GONE) }
            } else {
                views.setViewVisibility(R.id.empty_message, View.GONE)
                rows.forEachIndexed { index, row ->
                    val subject = data.subjects.getOrNull(index)
                    if (subject == null) {
                        views.setViewVisibility(row.rowId, View.GONE)
                    } else {
                        views.setViewVisibility(row.rowId, View.VISIBLE)
                        views.setTextViewText(row.nameId, subject.name)
                        views.setTextViewText(
                            row.statsId,
                            "${subject.attended}/${subject.total} - ${subject.percent.roundToInt()}%"
                        )
                        views.setOnClickPendingIntent(
                            row.presentId,
                            markIntent(context, subject.originalIndex, true)
                        )
                        views.setOnClickPendingIntent(
                            row.absentId,
                            markIntent(context, subject.originalIndex, false)
                        )
                    }
                }
            }

            return views
        }

        private fun markIntent(context: Context, subjectIndex: Int, present: Boolean): PendingIntent {
            val intent = Intent(context, AttendanceWidgetProvider::class.java).apply {
                action = ACTION_MARK_ATTENDANCE
                putExtra(EXTRA_SUBJECT_INDEX, subjectIndex)
                putExtra(EXTRA_PRESENT, present)
            }
            val requestCode = subjectIndex * 2 + if (present) 1 else 0
            return PendingIntent.getBroadcast(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }
    }
}

private data class WidgetRowViews(
    val rowId: Int,
    val nameId: Int,
    val statsId: Int,
    val presentId: Int,
    val absentId: Int
)

private data class AttendanceWidgetData(
    val subjects: List<WidgetSubject>,
    val attended: Int,
    val total: Int
) {
    val overallPercent: Double = if (total == 0) 0.0 else attended * 100.0 / total

    companion object {
        fun load(context: Context): AttendanceWidgetData {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val raw = prefs.getString("flutter.subjects", null) ?: return AttendanceWidgetData(emptyList(), 0, 0)
            return try {
                val subjects = JSONArray(raw).let { array ->
                    List(array.length()) { index ->
                        val item = array.getJSONObject(index)
                        WidgetSubject(
                            originalIndex = index,
                            name = item.optString("name", "Subject"),
                            attended = item.optInt("attended", 0),
                            total = item.optInt("total", 0),
                        )
                    }
                }
                AttendanceWidgetData(
                    subjects = subjects.take(4),
                    attended = subjects.sumOf { it.attended },
                    total = subjects.sumOf { it.total },
                )
            } catch (_: Exception) {
                AttendanceWidgetData(emptyList(), 0, 0)
            }
        }

        fun markAttendance(context: Context, subjectIndex: Int, present: Boolean) {
            if (subjectIndex < 0) return

            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val raw = prefs.getString("flutter.subjects", null) ?: return

            try {
                val subjects = JSONArray(raw)
                if (subjectIndex >= subjects.length()) return

                val subject = subjects.getJSONObject(subjectIndex)
                val attended = subject.optInt("attended", 0) + if (present) 1 else 0
                val total = subject.optInt("total", 0) + 1
                val history = subject.optJSONArray("history") ?: JSONArray()
                val record = JSONObject().apply {
                    put("date", Instant.now().toString())
                    put("present", present)
                }

                subject.put("attended", attended)
                subject.put("total", total)
                subject.put("history", JSONArray().apply {
                    put(record)
                    for (i in 0 until history.length()) {
                        put(history.get(i))
                    }
                })

                prefs.edit().putString("flutter.subjects", subjects.toString()).apply()
            } catch (_: Exception) {
                return
            }
        }
    }
}

private data class WidgetSubject(
    val originalIndex: Int,
    val name: String,
    val attended: Int,
    val total: Int
) {
    val percent: Double = if (total == 0) 0.0 else attended * 100.0 / total
}
