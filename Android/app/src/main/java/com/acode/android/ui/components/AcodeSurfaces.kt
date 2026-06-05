package com.acode.android.ui.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.acode.android.ui.theme.AcodeAlpha
import com.acode.android.ui.theme.AcodeColor
import com.acode.android.ui.theme.AcodeMotion
import com.acode.android.ui.theme.AcodeRadius
import com.acode.android.ui.theme.AcodeShadow
import com.acode.android.ui.theme.AcodeSize
import com.acode.android.ui.theme.AcodeSpace
import com.acode.android.ui.theme.AcodeStroke

@Composable
fun WhiteGlassBackground(modifier: Modifier = Modifier) {
    Box(
        modifier = modifier.background(
            Brush.linearGradient(
                listOf(
                    AcodeColor.BackgroundTop,
                    AcodeColor.BackgroundMiddle,
                    AcodeColor.BackgroundBottom,
                )
            )
        )
    ) {
        Box(
            modifier = Modifier
                .offset(x = (-70).dp, y = (-80).dp)
                .size(240.dp)
                .blur(34.dp)
                .background(Color.White.copy(alpha = 0.98f), CircleShape)
        )
    }
}

@Composable
fun AcodeGlassCard(
    modifier: Modifier = Modifier,
    corner: Dp = AcodeRadius.Chrome,
    fill: Color = AcodeColor.GlassCardFill,
    shadowAlpha: Float = AcodeShadow.CardAlpha,
    content: @Composable BoxScope.() -> Unit,
) {
    val shape = RoundedCornerShape(corner)
    Box(
        modifier = modifier
            .shadow(AcodeShadow.CardRadius, shape, ambientColor = Color.Black.copy(shadowAlpha), spotColor = Color.Black.copy(shadowAlpha))
            .clip(shape)
            .background(fill)
            .border(BorderStroke(AcodeStroke.Thin, AcodeColor.GlassCardStroke), shape)
            .border(BorderStroke(AcodeStroke.Thin, AcodeColor.GlassCardHairline), shape),
        content = content,
    )
}

@Composable
fun AcodeSoftGlass(
    modifier: Modifier = Modifier,
    shape: Shape = RoundedCornerShape(AcodeRadius.Control),
    fill: Color = AcodeColor.GlassFill,
    content: @Composable BoxScope.() -> Unit,
) {
    Box(
        modifier = modifier
            .shadow(AcodeShadow.ControlRadius, shape, ambientColor = Color.Black.copy(AcodeShadow.ControlAlpha), spotColor = Color.Black.copy(AcodeShadow.ControlAlpha))
            .clip(shape)
            .background(fill)
            .border(BorderStroke(AcodeStroke.Thin, AcodeColor.GlassStroke), shape),
        content = content,
    )
}

@Composable
fun AcodeIconButton(
    imageVector: ImageVector,
    contentDescription: String,
    modifier: Modifier = Modifier,
    size: Dp = AcodeSpace.Control,
    iconSize: Dp = AcodeSize.ToolbarIcon,
    enabled: Boolean = true,
    dark: Boolean = false,
    onClick: () -> Unit,
) {
    val interactionSource = remember { MutableInteractionSource() }
    val pressed by interactionSource.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = if (pressed) AcodeMotion.PressScale else 1f,
        animationSpec = tween(durationMillis = AcodeMotion.PressMillis),
        label = "acode-press-scale",
    )
    val shape = CircleShape
    val background = if (dark) AcodeColor.Ink else AcodeColor.GlassFill
    val foreground = if (dark) Color.White else AcodeColor.Ink

    Surface(
        modifier = modifier
            .size(size)
            .scale(scale)
            .alpha(if (pressed) AcodeAlpha.PressedOpacity else 1f)
            .shadow(AcodeShadow.ControlRadius, shape, ambientColor = Color.Black.copy(AcodeShadow.ControlAlpha), spotColor = Color.Black.copy(AcodeShadow.ControlAlpha))
            .clip(shape)
            .clickable(
                enabled = enabled,
                interactionSource = interactionSource,
                indication = null,
                onClick = onClick,
            ),
        shape = shape,
        color = background,
        border = if (dark) null else BorderStroke(AcodeStroke.Thin, AcodeColor.GlassStroke),
    ) {
        Box(contentAlignment = androidx.compose.ui.Alignment.Center) {
            Icon(
                imageVector = imageVector,
                contentDescription = contentDescription,
                tint = foreground.copy(alpha = if (enabled) 1f else AcodeAlpha.DisabledContent),
                modifier = Modifier.size(iconSize),
            )
        }
    }
}
