package com.spineapp.spine

import android.content.Context
import android.view.LayoutInflater
import android.widget.Button
import android.widget.ImageView
import android.widget.TextView
import com.google.android.gms.ads.nativead.MediaView
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

/**
 * Inflates the full-screen reel layout for a loaded native ad.
 *
 * Every asset has to be both populated *and* handed to the NativeAdView as its
 * matching `…View` property — the SDK measures clicks and viewability against
 * the views it was told about, so an asset that is only populated looks right
 * and reports nothing.
 *
 * Assets are optional per creative: a network may return an ad with no icon or
 * no body, and touching a view for an absent asset is what produces the
 * "ad rendered blank" reports. Hence the null checks and GONE handling.
 */
class ReelNativeAdFactory(private val context: Context) :
    GoogleMobileAdsPlugin.NativeAdFactory {

    override fun createNativeAd(
        nativeAd: NativeAd,
        customOptions: MutableMap<String, Any>?,
    ): NativeAdView {
        val adView = LayoutInflater.from(context)
            .inflate(R.layout.reel_native_ad, null) as NativeAdView

        val headline = adView.findViewById<TextView>(R.id.ad_headline)
        headline.text = nativeAd.headline
        adView.headlineView = headline

        val body = adView.findViewById<TextView>(R.id.ad_body)
        body.text = nativeAd.body
        body.visibility = if (nativeAd.body == null) android.view.View.GONE
                          else android.view.View.VISIBLE
        adView.bodyView = body

        val cta = adView.findViewById<Button>(R.id.ad_cta)
        cta.text = nativeAd.callToAction
        cta.visibility = if (nativeAd.callToAction == null) android.view.View.GONE
                         else android.view.View.VISIBLE
        adView.callToActionView = cta

        val icon = adView.findViewById<ImageView>(R.id.ad_icon)
        val iconAsset = nativeAd.icon
        if (iconAsset == null) {
            icon.visibility = android.view.View.GONE
        } else {
            icon.setImageDrawable(iconAsset.drawable)
            icon.visibility = android.view.View.VISIBLE
            adView.iconView = icon
        }

        val advertiser = adView.findViewById<TextView>(R.id.ad_advertiser)
        // Falls back to the store name: one or the other is always present,
        // and the attribution is not optional for policy.
        val attribution = nativeAd.advertiser ?: nativeAd.store
        advertiser.text = attribution
        advertiser.visibility = if (attribution == null) android.view.View.GONE
                                else android.view.View.VISIBLE
        adView.advertiserView = advertiser

        val media = adView.findViewById<MediaView>(R.id.ad_media)
        adView.mediaView = media

        // Last: this is what binds the populated views to the ad and starts
        // viewability tracking. Calling it before the assignments above would
        // register an empty view set.
        adView.setNativeAd(nativeAd)
        return adView
    }
}
