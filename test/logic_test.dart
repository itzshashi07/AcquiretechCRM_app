import 'package:acquiretech_crm/core/format.dart';
import 'package:acquiretech_crm/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('initials', () {
    test('uses first and last word', () => expect(initials('Priya Sharma'), 'PS'));
    test('ignores punctuation tokens', () => expect(initials('Priya Sharma (TEST)'), 'PT'));
    test('handles one word and empty', () {
      expect(initials('acme'), 'A');
      expect(initials('  '), '?');
    });
  });

  group('timeAgo', () {
    test('recent and slightly-future times read as just now', () {
      expect(timeAgo(DateTime.now()), 'just now');
      expect(timeAgo(DateTime.now().add(const Duration(seconds: 20))), 'just now');
    });
    test('minutes and hours', () {
      expect(timeAgo(DateTime.now().subtract(const Duration(minutes: 5))), '5m ago');
      expect(timeAgo(DateTime.now().subtract(const Duration(hours: 3))), '3h ago');
    });
  });

  group('notice titles', () {
    Notice n(String message) => Notice({'message': message, 'kind': 'leads', 'record_id': 'x', 'read': 0});
    test('website capture', () {
      expect(n('lead captured').title, 'New website enquiry');
      expect(n('lead captured').read, isFalse);
    });
    test('follow-ups and assignment', () {
      expect(n('lead follow-up overdue: Call Priya').title, 'Follow-up overdue');
      expect(n('lead follow-up overdue: Call Priya').detail, 'Call Priya');
      expect(n('lead reassigned').title, 'A lead was assigned to you');
      expect(n('lead stage changed: New Lead → Contacted').detail, 'New Lead → Contacted');
    });
  });

  group('records', () {
    test('parses numbers, custom fields and website source', () {
      final r = CrmRecord({
        'id': '1',
        'name': 'Deal',
        'amount': 1200,
        'source': 'Website',
        'customFields': {'budget': '40,000', 'submissionId': 'abc'},
      });
      expect(r.amount, 1200.0);
      expect(r.fromWebsite, isTrue);
      expect(r.customFields['budget'], '40,000');
    });
    test('kind parsing for notification links', () {
      final uri = Uri.parse('https://app/leads?record=abc');
      expect(RecordKind.parse(uri.pathSegments.first), RecordKind.leads);
      expect(uri.queryParameters['record'], 'abc');
      expect(RecordKind.parse('unknown'), isNull);
    });
    test('terminal stages', () {
      final w = Workflow.defaults();
      expect(w.isTerminal(RecordKind.leads, 'Converted'), isTrue);
      expect(w.isTerminal(RecordKind.leads, 'Contacted'), isFalse);
      expect(w.isTerminal(RecordKind.deals, 'Won'), isTrue);
    });
  });

  test('brief labels', () {
    expect(briefLabel('contactMethod'), 'Preferred contact');
    expect(briefLabel('detail_pageCount'), 'Page Count');
  });
}
