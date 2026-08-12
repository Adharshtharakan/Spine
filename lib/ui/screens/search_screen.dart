import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/spine_colors.dart';
import '../../core/theme/spine_text.dart';
import '../../state/library_controller.dart';
import '../widgets/book_row.dart';

/// Title, author, genre, or an idea's name. Nothing cleverer — finding a book
/// you half-remember is the whole job.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryController>();
    final results = library.search(_query);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Container(
            decoration: BoxDecoration(
              color: SpineColors.inkCard,
              border: Border.all(color: SpineColors.line),
              borderRadius: BorderRadius.circular(24),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                const Icon(
                  Icons.search,
                  size: 18,
                  color: SpineColors.parchmentDim,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    onChanged: (value) => setState(() => _query = value),
                    textInputAction: TextInputAction.search,
                    cursorColor: SpineColors.brass,
                    style: SpineText.secondary.copyWith(
                      color: SpineColors.parchment,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 13),
                      hintText: 'Search the shelf',
                      hintStyle: SpineText.secondary.copyWith(fontSize: 14),
                    ),
                  ),
                ),
                if (_query.isNotEmpty)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      _controller.clear();
                      setState(() => _query = '');
                      FocusScope.of(context).unfocus();
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.close,
                        size: 16,
                        color: SpineColors.parchmentDim,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: results.isEmpty
              ? Center(
                  child: Text(
                    'NOTHING ON THE SHELF MATCHES',
                    style: SpineText.label.copyWith(
                      color: SpineColors.parchmentDim,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: results.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: SpineColors.line),
                  itemBuilder: (context, index) => BookRow(book: results[index]),
                ),
        ),
      ],
    );
  }
}
