package com.acode.android.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Divider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.acode.android.ui.theme.AcodeAlpha
import com.acode.android.ui.theme.AcodeColor
import com.acode.android.ui.theme.AcodeRadius
import com.acode.android.ui.theme.AcodeSize
import com.acode.android.ui.theme.AcodeSpace
import com.acode.android.ui.theme.AcodeStroke
import com.acode.android.ui.theme.AcodeType

@Composable
fun SectionTitle(title: String, subtitle: String, modifier: Modifier = Modifier) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(AcodeSpace.MicroGap)) {
        Text(title, color = AcodeColor.Ink, fontSize = AcodeType.Title, fontWeight = FontWeight.SemiBold)
        Text(subtitle, color = AcodeColor.Muted, fontSize = AcodeType.CaptionSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
fun SettingsRow(
    title: String,
    subtitle: String,
    icon: ImageVector,
    modifier: Modifier = Modifier,
    showChevron: Boolean = true,
    onClick: (() -> Unit)? = null,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = AcodeSpace.RowPaddingX, vertical = AcodeSpace.RowPaddingY),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AcodeSpace.RowGap),
    ) {
        Icon(icon, contentDescription = null, tint = AcodeColor.Ink.copy(alpha = 0.58f), modifier = Modifier.size(AcodeSize.SettingsIcon))
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(AcodeSpace.NanoGap)) {
            Text(title, color = AcodeColor.Ink, fontSize = AcodeType.Body, fontWeight = FontWeight.SemiBold, maxLines = 1)
            Text(subtitle, color = AcodeColor.Muted, fontSize = AcodeType.Caption, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (showChevron) {
            Icon(Icons.Rounded.ChevronRight, contentDescription = null, tint = AcodeColor.Muted.copy(alpha = 0.55f), modifier = Modifier.size(AcodeSize.RowIcon))
        }
    }
}

@Composable
fun SettingsDivider(modifier: Modifier = Modifier) {
    Divider(
        modifier = modifier
            .padding(start = AcodeSpace.DividerStart)
            .fillMaxWidth(),
        color = Color.Black.copy(alpha = 0.08f),
        thickness = AcodeStroke.Thin,
    )
}

@Composable
fun BlackCapsuleButton(text: String, modifier: Modifier = Modifier, enabled: Boolean = true, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier.height(AcodeSize.PrimaryButtonHeight),
        colors = ButtonDefaults.buttonColors(
            containerColor = AcodeColor.Ink,
            contentColor = Color.White,
            disabledContainerColor = AcodeColor.Ink.copy(alpha = AcodeAlpha.PrimaryDisabledFill),
            disabledContentColor = Color.White.copy(alpha = AcodeAlpha.PrimaryDisabledText),
        ),
        shape = RoundedCornerShape(AcodeRadius.CircleControl),
        elevation = ButtonDefaults.buttonElevation(defaultElevation = 0.dp, pressedElevation = 0.dp),
        contentPadding = ButtonDefaults.ContentPadding,
    ) {
        Text(text, fontSize = AcodeType.Body, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
fun StatusDot(online: Boolean, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .size(AcodeSize.StatusDotLarge)
            .background(if (online) AcodeColor.Green else AcodeColor.Muted.copy(alpha = AcodeAlpha.OfflineDot), CircleShape)
    )
}

@Composable
fun SelectionPill(selected: Boolean, text: String, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .background(if (selected) AcodeColor.Ink else Color.Transparent, RoundedCornerShape(AcodeRadius.Control))
            .padding(horizontal = AcodeSpace.SegmentedPillX, vertical = AcodeSpace.SegmentedPillY),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = text,
            color = if (selected) Color.White else AcodeColor.Muted,
            fontSize = AcodeType.Body,
            fontWeight = FontWeight.SemiBold,
        )
    }
}
