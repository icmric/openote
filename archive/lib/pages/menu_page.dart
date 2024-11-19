import 'package:flutter/material.dart';
import '../widgets/custom_app_bar.dart';

class MenuPage extends StatefulWidget {
  @override
  _MenuPageState createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(currentRoute: '/menu'),
      body: Row(
        children: [
          SizedBox(
            width: 200,
            child: ListView(
              children: [
                TabBar(
                  controller: _tabController,
                  tabs: const [
                    //TODO: This needs to be split up into 3 seperate TabBars to be stacked vertically
                    Tab(text: 'General'),
                    Tab(text: 'Display'),
                    Tab(text: 'Advanced'),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                SettingsGroup(title: 'General Settings', settings: [
                  SettingWidget(type: SettingType.text, title: 'Username'),
                  SettingWidget(type: SettingType.dropdown, title: 'Language', options: ['English', 'Spanish', 'French']),
                  SettingWidget(type: SettingType.checkbox, title: 'Enable Notifications'),
                ]),
                SettingsGroup(title: 'Display Settings', settings: [
                  SettingWidget(type: SettingType.radio, title: 'Theme', options: ['Light', 'Dark']),
                  SettingWidget(type: SettingType.checkbox, title: 'Show Grid Lines'),
                ]),
                SettingsGroup(title: 'Advanced Settings', settings: [
                  SettingWidget(type: SettingType.text, title: 'API Key'),
                  SettingWidget(type: SettingType.nested, title: 'Developer Options', nestedSettings: [
                    SettingWidget(type: SettingType.checkbox, title: 'Enable Debug Mode'),
                    SettingWidget(type: SettingType.checkbox, title: 'Show Logs'),
                  ]),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsGroup extends StatelessWidget {
  final String title;
  final List<SettingWidget> settings;

  SettingsGroup({required this.title, required this.settings});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.all(16.0),
      children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ...settings,
      ],
    );
  }
}

enum SettingType { text, dropdown, checkbox, radio, nested }

class SettingWidget extends StatelessWidget {
  final SettingType type;
  final String title;
  final List<String>? options;
  final List<SettingWidget>? nestedSettings;

  SettingWidget({required this.type, required this.title, this.options, this.nestedSettings});

  @override
  Widget build(BuildContext context) {
    switch (type) {
      case SettingType.text:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: TextField(
            decoration: InputDecoration(
              labelText: title,
              border: OutlineInputBorder(),
            ),
          ),
        );
      case SettingType.dropdown:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: DropdownButtonFormField<String>(
            decoration: InputDecoration(
              labelText: title,
              border: OutlineInputBorder(),
            ),
            items: options?.map((String value) {
              return DropdownMenuItem<String>(
                value: value,
                child: Text(value),
              );
            }).toList(),
            onChanged: (newValue) {},
          ),
        );
      case SettingType.checkbox:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            children: [
              Checkbox(value: false, onChanged: (newValue) {}),
              Text(title),
            ],
          ),
        );
      case SettingType.radio:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 16)),
              ...options!.map((option) {
                return Row(
                  children: [
                    Radio(value: option, groupValue: null, onChanged: (newValue) {}),
                    Text(option),
                  ],
                );
              }).toList(),
            ],
          ),
        );
      case SettingType.nested:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Padding(
                padding: const EdgeInsets.only(left: 16.0),
                child: Column(
                  children: nestedSettings!,
                ),
              ),
            ],
          ),
        );
      default:
        return Container();
    }
  }
}
