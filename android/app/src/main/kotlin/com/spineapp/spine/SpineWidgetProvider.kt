package com.spineapp.spine

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * The home-screen widget: today's idea, in Spine's colours.
 *
 * It renders whatever the app last wrote to shared storage. There is no
 * background work here — the app republishes on launch, and the widget simply
 * shows the most recent thing it was given.
 */
class SpineWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.spine_widget).apply {
                val title = widgetData.getString("idea_title", null)
                val body = widgetData.getString("idea_body", null)
                val source = widgetData.getString("idea_source", null)

                if (title == null) {
                    // Before the app has run once there is nothing to show;
                    // an invitation beats an empty card.
                    setTextViewText(R.id.widget_title, "Open Spine")
                    setTextViewText(
                        R.id.widget_body,
                        "Today's idea will appear here.",
                    )
                    setTextViewText(R.id.widget_source, "")
                } else {
                    setTextViewText(R.id.widget_title, title)
                    setTextViewText(R.id.widget_body, body ?: "")
                    setTextViewText(R.id.widget_source, source?.uppercase() ?: "")
                }

                // Tapping anywhere opens the app.
                setOnClickPendingIntent(
                    R.id.widget_title,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
                )
                setOnClickPendingIntent(
                    R.id.widget_body,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
                )
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
