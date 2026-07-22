package com.ksled.controller.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.ksled.controller.ble.ScannedDevice
import com.ksled.controller.data.Preset
import com.ksled.controller.vm.AnimationType
import com.ksled.controller.vm.ControllerViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ControlScreen(vm: ControllerViewModel, device: ScannedDevice) {
    val ui by vm.ui.collectAsState()
    val nicknames by vm.nicknames.collectAsState()
    var tab by remember { mutableStateOf(0) }
    var showSaveDialog by remember { mutableStateOf(false) }
    var showNicknameDialog by remember { mutableStateOf(false) }

    val title = nicknames[device.address] ?: device.name

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text(title, fontWeight = FontWeight.Bold)
                        Text(
                            "Connected • ${device.model.prefix}",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.secondary,
                        )
                    }
                },
                navigationIcon = {
                    IconButton(onClick = { vm.disconnect() }) {
                        Icon(Icons.Filled.ArrowBack, contentDescription = "Disconnect")
                    }
                },
                actions = {
                    IconButton(onClick = { showNicknameDialog = true }) {
                        Icon(Icons.Filled.Edit, contentDescription = "Rename")
                    }
                    Switch(
                        checked = ui.powerOn,
                        onCheckedChange = { vm.togglePower(it) },
                    )
                    Spacer(Modifier.width(8.dp))
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                ),
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
        ) {
            ColorPreviewBar(hue = ui.hue, sat = ui.saturation, value = ui.brightness)
            Spacer(Modifier.height(16.dp))

            TabRow(selectedTabIndex = tab, containerColor = Color.Transparent) {
                listOf("Colour", "Presets", "Effects").forEachIndexed { i, label ->
                    Tab(selected = tab == i, onClick = { tab = i }, text = { Text(label) })
                }
            }
            Spacer(Modifier.height(16.dp))

            when (tab) {
                0 -> ColourTab(vm, ui.hue, ui.saturation, ui.brightness) { showSaveDialog = true }
                1 -> PresetsTab(vm)
                2 -> EffectsTab(vm)
            }
        }
    }

    if (showSaveDialog) {
        TextInputDialog(
            title = "Save preset",
            label = "Preset name",
            confirmText = "Save",
            onConfirm = { name -> if (name.isNotBlank()) vm.savePreset(name.trim()); showSaveDialog = false },
            onDismiss = { showSaveDialog = false },
        )
    }
    if (showNicknameDialog) {
        TextInputDialog(
            title = "Rename light",
            label = "Nickname",
            initial = nicknames[device.address] ?: "",
            confirmText = "Save",
            onConfirm = { name -> vm.setNickname(device.address, name.trim().ifBlank { null }); showNicknameDialog = false },
            onDismiss = { showNicknameDialog = false },
        )
    }
}

@Composable
private fun ColorPreviewBar(hue: Float, sat: Float, value: Float) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(72.dp)
            .clip(RoundedCornerShape(20.dp))
            .background(hsvColor(hue, sat, value.coerceIn(0.05f, 1f))),
    )
}

@Composable
private fun ColourTab(
    vm: ControllerViewModel,
    hue: Float,
    sat: Float,
    brightness: Float,
    onSavePreset: () -> Unit,
) {
    ColorWheel(
        hue = hue,
        saturation = sat,
        modifier = Modifier.padding(horizontal = 24.dp),
    ) { h, s -> vm.setHueSaturation(h, s) }

    Spacer(Modifier.height(24.dp))
    LabeledSlider(
        label = "Hue",
        value = hue / 360f,
        onValueChange = { vm.setHue(it * 360f) },
    )
    LabeledSlider(
        label = "Saturation",
        value = sat,
        onValueChange = { vm.setSaturation(it) },
    )
    LabeledSlider(
        label = "Brightness",
        value = brightness,
        onValueChange = { vm.setBrightness(it) },
    )
    Spacer(Modifier.height(8.dp))
    AssistChip(
        onClick = onSavePreset,
        label = { Text("Save as preset") },
        leadingIcon = { Icon(Icons.Filled.Add, contentDescription = null, Modifier.size(18.dp)) },
    )
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun PresetsTab(vm: ControllerViewModel) {
    val presets by vm.presets.collectAsState()
    Text(
        "Tap to apply • long-press to delete",
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    Spacer(Modifier.height(12.dp))
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        presets.forEach { preset -> PresetSwatch(preset, vm) }
    }
}

@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
private fun PresetSwatch(preset: Preset, vm: ControllerViewModel) {
    var confirmDelete by remember { mutableStateOf(false) }
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.width(96.dp)) {
        Box(
            modifier = Modifier
                .size(72.dp)
                .clip(RoundedCornerShape(18.dp))
                .background(Color(preset.r, preset.g, preset.b))
                .combinedClickable(
                    onClick = { vm.applyPreset(preset) },
                    onLongClick = { confirmDelete = true },
                ),
        )
        Spacer(Modifier.height(6.dp))
        Text(
            preset.name,
            style = MaterialTheme.typography.labelMedium,
            maxLines = 1,
            fontWeight = FontWeight.Medium,
        )
    }
    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("Delete preset?") },
            text = { Text("Remove \"${preset.name}\"?") },
            confirmButton = {
                TextButton(onClick = { vm.deletePreset(preset); confirmDelete = false }) {
                    Text("Delete")
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmDelete = false }) { Text("Cancel") }
            },
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun EffectsTab(vm: ControllerViewModel) {
    val ui by vm.ui.collectAsState()
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        AnimationType.values().forEach { anim ->
            EffectCard(
                anim = anim,
                selected = ui.animation == anim,
                onClick = { vm.startAnimation(anim) },
            )
        }
    }
    Spacer(Modifier.height(20.dp))
    LabeledSlider(
        label = "Speed",
        value = ui.speed,
        onValueChange = { vm.setSpeed(it) },
    )
    LabeledSlider(
        label = "Brightness",
        value = ui.brightness,
        onValueChange = { vm.setBrightness(it) },
    )
}

@Composable
private fun EffectCard(anim: AnimationType, selected: Boolean, onClick: () -> Unit) {
    Card(
        modifier = Modifier
            .width(104.dp)
            .height(88.dp)
            .clip(RoundedCornerShape(16.dp))
            .clickable(onClick = onClick),
        colors = CardDefaults.cardColors(
            containerColor = if (selected) MaterialTheme.colorScheme.primary
            else MaterialTheme.colorScheme.surface,
        ),
    ) {
        Column(
            modifier = Modifier.fillMaxSize().padding(8.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(anim.icon, style = MaterialTheme.typography.headlineSmall)
            Spacer(Modifier.height(4.dp))
            Text(
                anim.label,
                style = MaterialTheme.typography.labelMedium,
                color = if (selected) MaterialTheme.colorScheme.onPrimary
                else MaterialTheme.colorScheme.onSurface,
            )
        }
    }
}

@Composable
private fun LabeledSlider(label: String, value: Float, onValueChange: (Float) -> Unit) {
    Column(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
        Row(Modifier.fillMaxWidth()) {
            Text(label, style = MaterialTheme.typography.labelLarge)
            Spacer(Modifier.weight(1f))
            Text(
                "${(value * 100).toInt()}%",
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Slider(value = value, onValueChange = onValueChange)
    }
}

@Composable
private fun TextInputDialog(
    title: String,
    label: String,
    confirmText: String,
    initial: String = "",
    onConfirm: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    var text by remember { mutableStateOf(initial) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            OutlinedTextField(
                value = text,
                onValueChange = { text = it },
                label = { Text(label) },
                singleLine = true,
            )
        },
        confirmButton = { TextButton(onClick = { onConfirm(text) }) { Text(confirmText) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}
