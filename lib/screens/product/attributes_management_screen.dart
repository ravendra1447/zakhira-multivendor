import 'package:flutter/material.dart';
import 'package:whatsappchat/theme/app_colors.dart';
import 'package:whatsappchat/theme/app_typography.dart';
import 'package:whatsappchat/theme/app_spacing.dart';
import 'package:whatsappchat/widgets/gradient_button.dart';

class AttributesManagementScreen extends StatefulWidget {
  final Map<String, List<String>> attributes;
  final Map<String, String> selectedAttributeValues;

  const AttributesManagementScreen({
    super.key,
    required this.attributes,
    required this.selectedAttributeValues,
  });

  @override
  State<AttributesManagementScreen> createState() =>
      _AttributesManagementScreenState();
}

class _AttributesManagementScreenState
    extends State<AttributesManagementScreen> {
  late Map<String, List<String>> _attributes;
  late Map<String, String> _selectedAttributeValues;
  final Map<String, bool> _expandedAttributes = {};

  @override
  void initState() {
    super.initState();
    _attributes = Map<String, List<String>>.from(widget.attributes);
    _selectedAttributeValues =
        Map<String, String>.from(widget.selectedAttributeValues);
  }

  void _showAddAttributeModal() {
    final List<String> tempValues = [];
    final nameController = TextEditingController();
    final valueController = TextEditingController();
    bool nameFieldLocked = false;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              backgroundColor: AppColors.card(context),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title and close button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Add Attribute',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary(context),
                            ),
                          ),
                          Row(
                            children: [
                              // + button at top to add more values
                              GestureDetector(
                                onTap: () {
                                  final name = nameController.text.trim();
                                  final value = valueController.text.trim();
                                  if (name.isNotEmpty && value.isNotEmpty) {
                                    setModalState(() {
                                      // First time - lock name field and add value
                                      if (!nameFieldLocked) {
                                        nameFieldLocked = true;
                                        tempValues.add(value);
                                        valueController.clear();
                                      } else {
                                        // Subsequent times - just add value
                                        tempValues.add(value);
                                        valueController.clear();
                                      }
                                    });
                                  }
                                },
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF25D366),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.add,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: Icon(
                                  Icons.close,
                                  color: AppColors.textSecondary(context),
                                  size: 18,
                                ),
                                onPressed: () => Navigator.pop(ctx),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Show added values
                      if (tempValues.isNotEmpty) ...[
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: tempValues.map((value) {
                            return Chip(
                              backgroundColor: AppColors.surface(context),
                              label: Text(
                                value,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textPrimary(context),
                                ),
                              ),
                              onDeleted: () {
                                setModalState(() {
                                  tempValues.remove(value);
                                });
                              },
                              deleteIcon: Icon(
                                Icons.close,
                                size: 14,
                                color: AppColors.textSecondary(context),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 8),
                      ],
                      // Name and Value fields
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Name',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textPrimary(context),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: nameController,
                                  enabled: !nameFieldLocked,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textPrimary(context),
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Enter attribute name',
                                    hintStyle: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textHint(context),
                                    ),
                                    filled: true,
                                    fillColor: AppColors.surface(context),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(
                                        color: AppColors.border(context),
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(
                                        color: AppColors.border(context),
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(
                                        color: AppColors.primary(context),
                                      ),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Value',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textPrimary(context),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: valueController,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textPrimary(context),
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Enter attribute value',
                                    hintStyle: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textHint(context),
                                    ),
                                    filled: true,
                                    fillColor: AppColors.surface(context),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(
                                        color: AppColors.border(context),
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(
                                        color: AppColors.border(context),
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(
                                        color: AppColors.primary(context),
                                      ),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Done button
                      SizedBox(
                        width: double.infinity,
                        height: 36,
                        child: ElevatedButton(
                          onPressed: () {
                            final name = nameController.text.trim();
                            final value = valueController.text.trim();
                            
                            if (name.isNotEmpty && (value.isNotEmpty || tempValues.isNotEmpty)) {
                              setState(() {
                                if (!_attributes.containsKey(name)) {
                                  _attributes[name] = [];
                                }
                                // Add current value if filled
                                if (value.isNotEmpty && !_attributes[name]!.contains(value)) {
                                  _attributes[name]!.add(value);
                                }
                                // Add all temp values
                                for (var val in tempValues) {
                                  if (!_attributes[name]!.contains(val)) {
                                    _attributes[name]!.add(val);
                                  }
                                }
                                // Set selected value
                                if (_attributes[name]!.isNotEmpty) {
                                  _selectedAttributeValues[name] = _attributes[name]!.first;
                                }
                              });
                              Navigator.pop(ctx);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF25D366),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          child: const Text(
                            'Done',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showAddValueToAttribute(String attributeName) {
    final valueController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: AppColors.card(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Add Value to $attributeName',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        size: 18,
                        color: AppColors.textSecondary(context),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: valueController,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textPrimary(context),
                  ),
                  decoration: InputDecoration(
                    hintText: 'Enter value',
                    hintStyle: TextStyle(
                      color: AppColors.textHint(context),
                    ),
                    filled: true,
                    fillColor: AppColors.surface(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: AppColors.border(context),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: AppColors.border(context),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: AppColors.primary(context),
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 32,
                  child: ElevatedButton(
                    onPressed: () {
                      final value = valueController.text.trim();
                      if (value.isNotEmpty) {
                        setState(() {
                          if (!_attributes[attributeName]!.contains(value)) {
                            _attributes[attributeName]!.add(value);
                          }
                        });
                        Navigator.pop(ctx);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                    ),
                    child: const Text(
                      'Add',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showValueDropdown(String attributeName, List<String> values) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: AppColors.card(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Select $attributeName',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        size: 18,
                        color: AppColors.textSecondary(context),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...values.map((value) {
                  return ListTile(
                    title: Text(
                      value,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    onTap: () {
                      setState(() {
                        _selectedAttributeValues[attributeName] = value;
                      });
                      Navigator.pop(ctx);
                    },
                  );
                }).toList(),
              ],
            ),
          ),
        );
      },
    );
  }

  void _editAttributeValue(String attributeName, String currentValue) {
    final valueController = TextEditingController(text: currentValue);
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: AppColors.card(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Edit Value for $attributeName',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        size: 18,
                        color: AppColors.textSecondary(context),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: valueController,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textPrimary(context),
                  ),
                  decoration: InputDecoration(
                    hintText: 'Enter value',
                    hintStyle: TextStyle(
                      color: AppColors.textHint(context),
                    ),
                    filled: true,
                    fillColor: AppColors.surface(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: AppColors.border(context),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: AppColors.border(context),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: AppColors.primary(context),
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 32,
                  child: ElevatedButton(
                    onPressed: () {
                      final newValue = valueController.text.trim();
                      if (newValue.isNotEmpty && newValue != currentValue) {
                        setState(() {
                          final index =
                              _attributes[attributeName]!.indexOf(currentValue);
                          if (index != -1) {
                            _attributes[attributeName]![index] = newValue;
                            if (_selectedAttributeValues[attributeName] ==
                                currentValue) {
                              _selectedAttributeValues[attributeName] = newValue;
                            }
                          }
                        });
                        Navigator.pop(ctx);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                    ),
                    child: const Text(
                      'Save',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _deleteAttributeValue(String attributeName, String value) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.card(context),
          title: Text(
            'Delete Value',
            style: TextStyle(color: AppColors.textPrimary(context)),
          ),
          content: Text(
            'Are you sure you want to delete "$value" from "$attributeName"?',
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: TextStyle(color: AppColors.textSecondary(context)),
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _attributes[attributeName]!.remove(value);
                  if (_selectedAttributeValues[attributeName] == value) {
                    if (_attributes[attributeName]!.isNotEmpty) {
                      _selectedAttributeValues[attributeName] =
                          _attributes[attributeName]!.first;
                    } else {
                      _selectedAttributeValues.remove(attributeName);
                    }
                  }
                });
                Navigator.pop(ctx);
              },
              child: Text(
                'Delete',
                style: TextStyle(color: AppColors.error(context)),
              ),
            ),
          ],
        );
      },
    );
  }

  void _deleteAttribute(String attributeName) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.card(context),
          title: Text(
            'Delete Attribute',
            style: TextStyle(color: AppColors.textPrimary(context)),
          ),
          content: Text(
            'Are you sure you want to delete "$attributeName"?',
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: TextStyle(color: AppColors.textSecondary(context)),
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _attributes.remove(attributeName);
                  _selectedAttributeValues.remove(attributeName);
                });
                Navigator.pop(ctx);
              },
              child: Text(
                'Delete',
                style: TextStyle(color: AppColors.error(context)),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : const Color(0xFF1F1F1F),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: const Color(0xDEFFFFFF)),
          onPressed: () {
            Navigator.pop(context, {
              'attributes': _attributes,
              'selectedValues': _selectedAttributeValues,
            });
          },
        ),
        title: Text(
          'Attributes',
          style: TextStyle(
            color: const Color(0xDEFFFFFF),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.primary(context),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.add,
                color: Colors.white,
                size: 18,
              ),
            ),
            onPressed: _showAddAttributeModal,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_attributes.isEmpty)
              Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'No attributes added yet',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                ),
              )
            else
              ..._attributes.entries.map((e) {
                final values = e.value;
                final selectedValue = _selectedAttributeValues[e.key] ??
                    (values.isNotEmpty ? values.first : '');
                final isExpanded = _expandedAttributes[e.key] ?? false;
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.card(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border(context)),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.textPrimary(context).withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Checkbox on left side
                      Checkbox(
                        value: _selectedAttributeValues.containsKey(e.key),
                        onChanged: (bool? value) {
                          setState(() {
                            if (value == true) {
                              // Select first value if not selected
                              if (!_selectedAttributeValues.containsKey(e.key)) {
                                _selectedAttributeValues[e.key] = values.isNotEmpty
                                    ? values.first
                                    : '';
                              }
                            } else {
                              // Remove selection
                              _selectedAttributeValues.remove(e.key);
                            }
                          });
                        },
                        activeColor: AppColors.primary(context),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          e.key,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary(context),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _showValueDropdown(e.key, values),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surface(context),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppColors.border(context),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    selectedValue,
                                    style: TextStyle(fontSize: 13, color: AppColors.textPrimary(context)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.keyboard_arrow_down,
                                  size: 16,
                                  color: AppColors.textSecondary(context),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Expand/Collapse arrow
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _expandedAttributes[e.key] = !isExpanded;
                          });
                        },
                        child: Icon(
                          isExpanded
                              ? Icons.keyboard_arrow_up
                              : Icons.chevron_right,
                          color: AppColors.textSecondary(context),
                          size: 20,
                        ),
                      ),
                      // Show buttons only when expanded
                      if (isExpanded) ...[
                        const SizedBox(width: 4),
                        // + button
                        GestureDetector(
                          onTap: () => _showAddValueToAttribute(e.key),
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: AppColors.primary(context),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.add,
                              color: Colors.white,
                              size: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        // Edit button
                        GestureDetector(
                          onTap: () =>
                              _editAttributeValue(e.key, selectedValue),
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: AppColors.info(context),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.edit,
                              color: Colors.white,
                              size: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        // Delete button (deletes whole attribute)
                        GestureDetector(
                          onTap: () => _deleteAttribute(e.key),
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: AppColors.error(context),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.delete,
                              color: Colors.white,
                              size: 14,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            const SizedBox(height: 24),
            // Save button at bottom
            GradientButton(
              text: 'Save',
              onPressed: () {
                Navigator.pop(context, {
                  'attributes': _attributes,
                  'selectedValues': _selectedAttributeValues,
                });
              },
              height: 48,
            ),
          ],
        ),
      ),
    );
  }
}

