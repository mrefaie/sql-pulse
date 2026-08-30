// SQL Pulse — seed catalog data (large dataset, deterministically generated).
// Ported from data.js.
import 'dart:math' as math;
import 'models.dart';
import 'engines.dart';

ColumnDef _col(String name, String type,
    {bool pk = false, bool nullable = true, bool ai = false, String? fkTable, String? fkCol}) {
  return ColumnDef(
      name: name, type: type, pk: pk, nullable: nullable, ai: ai, fkTable: fkTable, fkCol: fkCol);
}

String _pad(int n) => n.toString().padLeft(2, '0');
String _dt(int y, int m, int d, [int h = 9, int mi = 0]) =>
    '$y-${_pad(m)}-${_pad(d)} ${_pad(h)}:${_pad(mi)}:00';
String _date(int y, int m, int d) => '$y-${_pad(m)}-${_pad(d)}';
T _pick<T>(List<T> arr, int i) => arr[((i % arr.length) + arr.length) % arr.length];
List<T> _range<T>(int n, T Function(int) f) => List.generate(n, f);

double _rnd(int seed) {
  final x = math.sin(seed * 99.13 + 17.7) * 43758.5453;
  return x - x.floorToDouble();
}

int _ri(int seed, int min, int max) => min + (_rnd(seed) * (max - min + 1)).floor();

double _round1(double x) => (x * 10).round() / 10;
double _round2(double x) => (x * 100).round() / 100;

const _first = ['John', 'Sarah', 'Alex', 'Emma', 'David', 'Maria', 'James', 'Olivia', 'Daniel', 'Sophia', 'Lucas', 'Mia', 'Ethan', 'Ava', 'Noah', 'Isabella', 'Liam', 'Grace', 'Mason', 'Chloe', 'Ryan', 'Zoe', 'Kelly', 'Anthony', 'Nina', 'Omar', 'Priya', 'Wei', 'Hana', 'Diego'];
const _last = ['Doe', 'Smith', 'Jones', 'Miller', 'Davis', 'Garcia', 'Wilson', 'Moore', 'Taylor', 'Anderson', 'Chen', 'Patel', 'Kim', 'Nguyen', 'Lopez', 'Khan', 'Müller', 'Rossi', 'Silva', 'Cohen'];
const _country = ['US', 'UK', 'DE', 'FR', 'CA', 'AU', 'JP', 'BR', 'IN', 'NL', 'ES', 'SE'];
const _city = ['New York', 'London', 'Berlin', 'Paris', 'Toronto', 'Sydney', 'Tokyo', 'São Paulo', 'Mumbai', 'Amsterdam', 'Madrid', 'Stockholm'];

Catalog _eCommerce() {
  const roles = ['Customer', 'VIP', 'Customer', 'Customer', 'Moderator', 'Customer', 'VIP'];
  const ustatus = ['Active', 'Active', 'Active', 'Dormant', 'Suspended'];
  final users = _range(44, (i) {
    final id = i + 1;
    final f = _pick(_first, i), l = _pick(_last, i * 3 + 1);
    return <String, Object?>{
      'id': id,
      'username': (f + l).toLowerCase() + (id % 7 == 0 ? '$id' : ''),
      'email': '${'$f.$l'.toLowerCase()}@example.com',
      'full_name': '$f $l',
      'role': _pick(roles, i),
      'country': _pick(_country, i * 2),
      'marketing_opt_in': i % 3 == 0 ? 1 : 0,
      'status': _pick(ustatus, _ri(id, 0, 4)),
      'created_at': _dt(2025, (i % 12) + 1, (i % 27) + 1, 8 + (i % 12), i % 60),
    };
  });

  const supNames = ['Acme Supplies', 'Globex Corp', 'Initech Goods', 'Umbrella Trade', 'Stark Industries', 'Wayne Logistics', 'Soylent Foods', 'Hooli Hardware', 'Pied Piper Co', 'Vandelay Imports', 'Wonka Goods', 'Cyberdyne Parts', 'Tyrell Supply', 'Nakatomi Trade'];
  final suppliers = _range(14, (i) => <String, Object?>{
        'supplier_id': i + 1,
        'company': supNames[i],
        'contact_email': 'sales@${supNames[i].split(' ')[0].toLowerCase()}.com',
        'country': _pick(_country, i),
        'lead_time_days': _ri(i + 5, 2, 21),
        'active': i % 5 == 0 ? 0 : 1,
      });

  const catNames = ['Electronics', 'Furniture', 'Home & Kitchen', 'Apparel', 'Sports', 'Beauty', 'Toys', 'Books', 'Garden', 'Automotive', 'Grocery', 'Office'];
  final categories = _range(12, (i) => <String, Object?>{
        'category_id': i + 1,
        'name': catNames[i],
        'slug': catNames[i].toLowerCase().replaceAll(RegExp(r'[^a-z]+'), '-'),
        'parent_id': i < 4 ? null : _ri(i, 1, 4),
        'product_count': _ri(i + 2, 4, 60),
      });

  const pAdj = ['Wireless', 'Ergonomic', 'Stainless', 'Bluetooth', 'Organic', 'Premium', 'Compact', 'Smart', 'Portable', 'Heavy-duty', 'Eco', 'Ultra'];
  const pNoun = ['Headphones', 'Office Chair', 'Water Bottle', 'Keyboard', 'Backpack', 'Monitor', 'Desk Lamp', 'Webcam', 'Speaker', 'Charger', 'Mouse', 'Notebook', 'Blender', 'Camera', 'Router'];
  final products = _range(40, (i) => <String, Object?>{
        'product_id': 501 + i,
        'name': '${_pick(pAdj, i)} ${_pick(pNoun, i * 2 + 1)}',
        'sku': '${_pick(pNoun, i * 2 + 1).substring(0, 4).toUpperCase()}-${1000 + i}',
        'price': _round2(_ri(i + 1, 9, 499) + 0.99),
        'stock': _ri(i + 9, 0, 220),
        'category_id': _ri(i, 1, 12),
        'supplier_id': _ri(i + 3, 1, 14),
        'rating': _round1(3 + _rnd(i) * 2),
        'created_at': _dt(2025, (i % 12) + 1, (i % 26) + 1),
      });

  final addresses = _range(50, (i) => <String, Object?>{
        'address_id': i + 1,
        'user_id': _ri(i, 1, 44),
        'line1': '${_ri(i, 10, 999)} ${_pick(['Main', 'Oak', 'Pine', 'Elm', 'Cedar', 'Park'], i)} St',
        'city': _pick(_city, i * 2),
        'country': _pick(_country, i),
        'postal_code': '${10000 + _ri(i, 0, 89999)}',
        'is_default': i % 4 == 0 ? 1 : 0,
      });

  const pmethods = ['Visa', 'Mastercard', 'PayPal', 'Apple Pay', 'Bank Transfer'];
  const pstatus = ['Captured', 'Captured', 'Captured', 'Refunded', 'Pending', 'Failed'];
  final payments = _range(64, (i) => <String, Object?>{
        'payment_id': 9001 + i,
        'method': _pick(pmethods, i),
        'amount': _round2(_ri(i + 1, 12, 950) + 0.5),
        'status': _pick(pstatus, _ri(i, 0, 5)),
        'paid_at': _dt(2026, (i % 5) + 1, (i % 27) + 1, 10 + (i % 10), i % 59),
      });

  const ostatus = ['Completed', 'Completed', 'Processing', 'Shipped', 'Cancelled', 'Refunded'];
  final orders = _range(64, (i) => <String, Object?>{
        'order_id': 1001 + i,
        'user_id': _ri(i, 1, 44),
        'order_date': _dt(2026, (i % 5) + 1, (i % 27) + 1, 9 + (i % 12), i % 59),
        'status': _pick(ostatus, _ri(i + 1, 0, 5)),
        'total_amount': _round2(_ri(i + 2, 15, 1200) + 0.5),
        'shipping_address_id': _ri(i, 1, 50),
        'payment_id': 9001 + i,
      });

  final orderItems = _range(150, (i) {
    final oid = 1001 + _ri(i, 0, 63);
    final pid = 501 + _ri(i + 7, 0, 39);
    final p = products[pid - 501];
    return <String, Object?>{
      'item_id': i + 1,
      'order_id': oid,
      'product_id': pid,
      'quantity': _ri(i + 3, 1, 6),
      'unit_price': p['price'],
    };
  });

  const rtitles = ['Great value', 'Works perfectly', 'Not as described', 'Highly recommend', 'Average quality', 'Exceeded expectations', 'Would buy again', 'Disappointed'];
  final reviews = _range(56, (i) => <String, Object?>{
        'review_id': i + 1,
        'product_id': 501 + _ri(i, 0, 39),
        'user_id': _ri(i + 5, 1, 44),
        'rating': _ri(i, 1, 5),
        'title': _pick(rtitles, i),
        'created_at': _dt(2026, (i % 5) + 1, (i % 27) + 1),
      });

  final t = <String, TableDef>{};
  t['users'] = TableDef(name: 'users', columns: [
    _col('id', 'INT', pk: true, ai: true, nullable: false),
    _col('username', 'VARCHAR(50)', nullable: false),
    _col('email', 'VARCHAR(120)', nullable: false),
    _col('full_name', 'VARCHAR(100)'),
    _col('role', 'VARCHAR(30)', nullable: false),
    _col('country', 'CHAR(2)'),
    _col('marketing_opt_in', 'TINYINT(1)', nullable: false),
    _col('status', 'VARCHAR(20)', nullable: false),
    _col('created_at', 'DATETIME', nullable: false),
  ], rows: users);
  t['categories'] = TableDef(name: 'categories', columns: [
    _col('category_id', 'INT', pk: true, ai: true, nullable: false),
    _col('name', 'VARCHAR(50)', nullable: false),
    _col('slug', 'VARCHAR(60)', nullable: false),
    _col('parent_id', 'INT', fkTable: 'categories', fkCol: 'category_id'),
    _col('product_count', 'INT', nullable: false),
  ], rows: categories);
  t['suppliers'] = TableDef(name: 'suppliers', columns: [
    _col('supplier_id', 'INT', pk: true, ai: true, nullable: false),
    _col('company', 'VARCHAR(80)', nullable: false),
    _col('contact_email', 'VARCHAR(120)'),
    _col('country', 'CHAR(2)'),
    _col('lead_time_days', 'INT', nullable: false),
    _col('active', 'TINYINT(1)', nullable: false),
  ], rows: suppliers);
  t['products'] = TableDef(name: 'products', columns: [
    _col('product_id', 'INT', pk: true, ai: true, nullable: false),
    _col('name', 'VARCHAR(120)', nullable: false),
    _col('sku', 'VARCHAR(24)', nullable: false),
    _col('price', 'DECIMAL(10,2)', nullable: false),
    _col('stock', 'INT', nullable: false),
    _col('category_id', 'INT', nullable: false, fkTable: 'categories', fkCol: 'category_id'),
    _col('supplier_id', 'INT', nullable: false, fkTable: 'suppliers', fkCol: 'supplier_id'),
    _col('rating', 'DECIMAL(2,1)'),
    _col('created_at', 'DATETIME', nullable: false),
  ], rows: products);
  t['addresses'] = TableDef(name: 'addresses', columns: [
    _col('address_id', 'INT', pk: true, ai: true, nullable: false),
    _col('user_id', 'INT', nullable: false, fkTable: 'users', fkCol: 'id'),
    _col('line1', 'VARCHAR(120)', nullable: false),
    _col('city', 'VARCHAR(60)'),
    _col('country', 'CHAR(2)'),
    _col('postal_code', 'VARCHAR(12)'),
    _col('is_default', 'TINYINT(1)', nullable: false),
  ], rows: addresses);
  t['payments'] = TableDef(name: 'payments', columns: [
    _col('payment_id', 'INT', pk: true, ai: true, nullable: false),
    _col('method', 'VARCHAR(20)', nullable: false),
    _col('amount', 'DECIMAL(10,2)', nullable: false),
    _col('status', 'VARCHAR(20)', nullable: false),
    _col('paid_at', 'DATETIME', nullable: false),
  ], rows: payments);
  t['orders'] = TableDef(name: 'orders', columns: [
    _col('order_id', 'INT', pk: true, ai: true, nullable: false),
    _col('user_id', 'INT', nullable: false, fkTable: 'users', fkCol: 'id'),
    _col('order_date', 'DATETIME', nullable: false),
    _col('status', 'VARCHAR(20)', nullable: false),
    _col('total_amount', 'DECIMAL(10,2)', nullable: false),
    _col('shipping_address_id', 'INT', fkTable: 'addresses', fkCol: 'address_id'),
    _col('payment_id', 'INT', fkTable: 'payments', fkCol: 'payment_id'),
  ], rows: orders);
  t['order_items'] = TableDef(name: 'order_items', columns: [
    _col('item_id', 'INT', pk: true, ai: true, nullable: false),
    _col('order_id', 'INT', nullable: false, fkTable: 'orders', fkCol: 'order_id'),
    _col('product_id', 'INT', nullable: false, fkTable: 'products', fkCol: 'product_id'),
    _col('quantity', 'INT', nullable: false),
    _col('unit_price', 'DECIMAL(10,2)', nullable: false),
  ], rows: orderItems);
  t['reviews'] = TableDef(name: 'reviews', columns: [
    _col('review_id', 'INT', pk: true, ai: true, nullable: false),
    _col('product_id', 'INT', nullable: false, fkTable: 'products', fkCol: 'product_id'),
    _col('user_id', 'INT', nullable: false, fkTable: 'users', fkCol: 'id'),
    _col('rating', 'TINYINT', nullable: false),
    _col('title', 'VARCHAR(120)'),
    _col('created_at', 'DATETIME', nullable: false),
  ], rows: reviews);

  return Catalog(
    label: 'e_commerce',
    tables: t,
    views: [
      {'name': 'v_revenue_by_user', 'definition': 'CREATE VIEW v_revenue_by_user AS\nSELECT u.username, SUM(o.total_amount) AS spent\nFROM users u\nJOIN orders o ON u.id = o.user_id\nGROUP BY u.username;'},
      {'name': 'v_low_stock', 'definition': 'CREATE VIEW v_low_stock AS\nSELECT product_id, name, stock\nFROM products\nWHERE stock < 15\nORDER BY stock ASC;'},
      {'name': 'v_order_items_detailed', 'definition': 'CREATE VIEW v_order_items_detailed AS\nSELECT oi.item_id, o.order_id, p.name, oi.quantity\nFROM order_items oi\nJOIN orders o ON oi.order_id = o.order_id\nJOIN products p ON oi.product_id = p.product_id;'},
      {'name': 'v_top_rated', 'definition': 'CREATE VIEW v_top_rated AS\nSELECT p.name, AVG(r.rating) avg_rating, COUNT(*) reviews\nFROM products p JOIN reviews r ON p.product_id = r.product_id\nGROUP BY p.name HAVING reviews > 3;'},
    ],
    procedures: [
      {'name': 'CalculateTotalSales', 'params': '', 'definition': 'CREATE PROCEDURE CalculateTotalSales()\nBEGIN\n  SELECT SUM(total_amount) AS revenue FROM orders;\nEND'},
      {'name': 'UpdateProductStock', 'params': 'p_id INT, qty INT', 'definition': 'CREATE PROCEDURE UpdateProductStock(p_id INT, qty INT)\nBEGIN\n  UPDATE products SET stock = stock - qty WHERE product_id = p_id;\nEND'},
      {'name': 'ArchiveDormantUsers', 'params': '', 'definition': "CREATE PROCEDURE ArchiveDormantUsers()\nBEGIN\n  UPDATE users SET status = 'Archived' WHERE status = 'Dormant';\nEND"},
    ],
    functions: [
      {'name': 'GetDiscountMultiplier', 'params': 'user_role VARCHAR(20)', 'returns': 'DECIMAL(3,2)', 'definition': "CREATE FUNCTION GetDiscountMultiplier(user_role VARCHAR(20))\nRETURNS DECIMAL(3,2)\nBEGIN\n  IF user_role = 'VIP' THEN RETURN 0.90;\n  ELSE RETURN 1.00;\n  END IF;\nEND"},
      {'name': 'OrderItemCount', 'params': 'o_id INT', 'returns': 'INT', 'definition': 'CREATE FUNCTION OrderItemCount(o_id INT)\nRETURNS INT\nBEGIN\n  RETURN (SELECT COUNT(*) FROM order_items WHERE order_id = o_id);\nEND'},
    ],
    triggers: [
      {'name': 'after_order_item_inserted', 'event': 'AFTER INSERT', 'target': 'order_items', 'definition': 'CREATE TRIGGER after_order_item_inserted\nAFTER INSERT ON order_items FOR EACH ROW\nBEGIN\n  UPDATE products SET stock = stock - NEW.quantity WHERE product_id = NEW.product_id;\nEND'},
      {'name': 'before_review_insert', 'event': 'BEFORE INSERT', 'target': 'reviews', 'definition': 'CREATE TRIGGER before_review_insert\nBEFORE INSERT ON reviews FOR EACH ROW\nBEGIN\n  IF NEW.rating > 5 THEN SET NEW.rating = 5; END IF;\nEND'},
    ],
    er: {
      'users': const Offset2(24, 36), 'addresses': const Offset2(24, 300), 'reviews': const Offset2(24, 560),
      'orders': const Offset2(252, 36), 'order_items': const Offset2(252, 300), 'payments': const Offset2(252, 560),
      'products': const Offset2(480, 36), 'categories': const Offset2(480, 300), 'suppliers': const Offset2(480, 560),
    },
    relations: [
      Relation('orders', 'users', 'orders.user_id → users.id', 'accent'),
      Relation('order_items', 'orders', 'order_items.order_id → orders.order_id', 'warn'),
      Relation('order_items', 'products', 'order_items.product_id → products.product_id', 'info'),
      Relation('products', 'categories', 'products.category_id → categories.category_id', 'lime'),
      Relation('products', 'suppliers', 'products.supplier_id → suppliers.supplier_id', 'violet'),
      Relation('addresses', 'users', 'addresses.user_id → users.id', 'accent'),
      Relation('reviews', 'products', 'reviews.product_id → products.product_id', 'info'),
      Relation('orders', 'payments', 'orders.payment_id → payments.payment_id', 'pink'),
    ],
  );
}

Catalog _hrAnalytics() {
  const deptNames = ['Engineering', 'Sales', 'Marketing', 'Administration', 'Finance', 'Support', 'Design', 'Operations'];
  final departments = _range(8, (i) => <String, Object?>{
        'dept_id': i + 1,
        'dept_name': deptNames[i],
        'manager_id': 1001 + i,
        'budget': _ri(i + 1, 200, 2000) * 1000,
      });
  const titles = ['Junior', 'Mid', 'Senior', 'Lead', 'Principal'];
  final employees = _range(60, (i) {
    final f = _pick(_first, i * 2), l = _pick(_last, i + 2);
    return <String, Object?>{
      'emp_id': 1001 + i,
      'first_name': f,
      'last_name': l,
      'email': '${(f[0] + l).toLowerCase()}@corp.io',
      'dept_id': _ri(i, 1, 8),
      'title': '${_pick(titles, _ri(i, 0, 4))} ${_pick(['Engineer', 'Analyst', 'Manager', 'Designer', 'Rep'], i)}',
      'salary': _ri(i + 3, 42, 185) * 1000,
      'manager_id': i < 8 ? null : 1001 + _ri(i, 0, 7),
      'hire_date': _date(2014 + (i % 11), (i % 12) + 1, (i % 27) + 1),
    };
  });
  final projects = _range(16, (i) => <String, Object?>{
        'project_id': i + 1,
        'name': '${_pick(['Apollo', 'Titan', 'Nimbus', 'Falcon', 'Orion', 'Vega', 'Helios', 'Atlas'], i)} ${_pick(['Phase 1', 'Rollout', 'Migration', 'Revamp'], i)}',
        'dept_id': _ri(i, 1, 8),
        'lead_id': 1001 + _ri(i, 0, 59),
        'status': _pick(['Active', 'Active', 'Completed', 'On Hold'], i),
        'budget': _ri(i + 2, 20, 500) * 1000,
      });
  final assignments = _range(80, (i) => <String, Object?>{
        'assignment_id': i + 1,
        'emp_id': 1001 + _ri(i, 0, 59),
        'project_id': _ri(i, 1, 16),
        'hours_per_week': _ri(i + 1, 4, 40),
        'role': _pick(['Contributor', 'Reviewer', 'Owner', 'Observer'], i),
      });
  final timesheets = _range(90, (i) => <String, Object?>{
        'ts_id': i + 1,
        'emp_id': 1001 + _ri(i, 0, 59),
        'week_start': _date(2026, (i % 5) + 1, ((i * 7) % 27) + 1),
        'hours': _ri(i + 2, 20, 50),
        'approved': i % 3 == 0 ? 0 : 1,
      });

  final t = <String, TableDef>{};
  t['departments'] = TableDef(name: 'departments', columns: [
    _col('dept_id', 'INT', pk: true, nullable: false),
    _col('dept_name', 'VARCHAR(50)', nullable: false),
    _col('manager_id', 'INT', fkTable: 'employees', fkCol: 'emp_id'),
    _col('budget', 'DECIMAL(12,2)', nullable: false),
  ], rows: departments);
  t['employees'] = TableDef(name: 'employees', columns: [
    _col('emp_id', 'INT', pk: true, ai: true, nullable: false),
    _col('first_name', 'VARCHAR(50)', nullable: false),
    _col('last_name', 'VARCHAR(50)', nullable: false),
    _col('email', 'VARCHAR(120)'),
    _col('dept_id', 'INT', nullable: false, fkTable: 'departments', fkCol: 'dept_id'),
    _col('title', 'VARCHAR(60)'),
    _col('salary', 'DECIMAL(12,2)', nullable: false),
    _col('manager_id', 'INT', fkTable: 'employees', fkCol: 'emp_id'),
    _col('hire_date', 'DATE', nullable: false),
  ], rows: employees);
  t['projects'] = TableDef(name: 'projects', columns: [
    _col('project_id', 'INT', pk: true, ai: true, nullable: false),
    _col('name', 'VARCHAR(80)', nullable: false),
    _col('dept_id', 'INT', nullable: false, fkTable: 'departments', fkCol: 'dept_id'),
    _col('lead_id', 'INT', fkTable: 'employees', fkCol: 'emp_id'),
    _col('status', 'VARCHAR(20)', nullable: false),
    _col('budget', 'DECIMAL(12,2)'),
  ], rows: projects);
  t['assignments'] = TableDef(name: 'assignments', columns: [
    _col('assignment_id', 'INT', pk: true, ai: true, nullable: false),
    _col('emp_id', 'INT', nullable: false, fkTable: 'employees', fkCol: 'emp_id'),
    _col('project_id', 'INT', nullable: false, fkTable: 'projects', fkCol: 'project_id'),
    _col('hours_per_week', 'INT', nullable: false),
    _col('role', 'VARCHAR(30)'),
  ], rows: assignments);
  t['timesheets'] = TableDef(name: 'timesheets', columns: [
    _col('ts_id', 'INT', pk: true, ai: true, nullable: false),
    _col('emp_id', 'INT', nullable: false, fkTable: 'employees', fkCol: 'emp_id'),
    _col('week_start', 'DATE', nullable: false),
    _col('hours', 'INT', nullable: false),
    _col('approved', 'TINYINT(1)', nullable: false),
  ], rows: timesheets);

  return Catalog(
    label: 'hr_analytics',
    tables: t,
    views: [
      {'name': 'v_avg_salary_by_dept', 'definition': 'CREATE VIEW v_avg_salary_by_dept AS\nSELECT d.dept_name, AVG(e.salary) avg_salary\nFROM employees e JOIN departments d ON e.dept_id = d.dept_id\nGROUP BY d.dept_name;'},
      {'name': 'v_project_load', 'definition': 'CREATE VIEW v_project_load AS\nSELECT p.name, SUM(a.hours_per_week) total_hours\nFROM projects p JOIN assignments a ON p.project_id = a.project_id\nGROUP BY p.name;'},
    ],
    procedures: [
      {'name': 'GiveRaise', 'params': 'dept INT, pct DECIMAL(4,2)', 'definition': 'CREATE PROCEDURE GiveRaise(dept INT, pct DECIMAL(4,2))\nBEGIN\n  UPDATE employees SET salary = salary * (1 + pct) WHERE dept_id = dept;\nEND'},
    ],
    functions: [
      {'name': 'Tenure', 'params': 'h DATE', 'returns': 'INT', 'definition': 'CREATE FUNCTION Tenure(h DATE)\nRETURNS INT\nBEGIN\n  RETURN TIMESTAMPDIFF(YEAR, h, CURDATE());\nEND'},
    ],
    triggers: [],
    er: {
      'departments': const Offset2(252, 40), 'employees': const Offset2(24, 300), 'projects': const Offset2(252, 320), 'assignments': const Offset2(480, 300), 'timesheets': const Offset2(24, 560),
    },
    relations: [
      Relation('employees', 'departments', 'employees.dept_id → departments.dept_id', 'accent'),
      Relation('projects', 'departments', 'projects.dept_id → departments.dept_id', 'warn'),
      Relation('projects', 'employees', 'projects.lead_id → employees.emp_id', 'lime'),
      Relation('assignments', 'employees', 'assignments.emp_id → employees.emp_id', 'info'),
      Relation('assignments', 'projects', 'assignments.project_id → projects.project_id', 'violet'),
      Relation('timesheets', 'employees', 'timesheets.emp_id → employees.emp_id', 'pink'),
    ],
  );
}

Catalog _iot() {
  const dtypes = ['Temperature', 'Humidity', 'Pressure', 'Motion', 'CO2', 'Vibration'];
  const locs = ['Building A · Floor 1', 'Building A · Floor 2', 'Building B · Server Room', 'Main Lobby', 'Warehouse', 'Roof', 'Parking', 'Lab 3'];
  final devices = _range(24, (i) => <String, Object?>{
        'device_id': '${_pick(['SEN', 'HVAC', 'GW', 'CAM'], i)}-${_pad(i + 1)}',
        'device_name': '${_pick(dtypes, i)} ${_pick(['Sensor', 'Probe', 'Controller', 'Node'], i)}',
        'location': _pick(locs, i),
        'firmware_id': _ri(i, 1, 8),
        'status': _pick(['Active', 'Active', 'Active', 'Maintenance', 'Offline'], _ri(i, 0, 4)),
        'last_seen': _dt(2026, 5, 31, 8 + (i % 12), i % 59),
      });
  const metrics = ['temperature', 'humidity', 'pressure', 'co2', 'vibration'];
  final telemetryLogs = _range(200, (i) => <String, Object?>{
        'log_id': i + 1,
        'device_id': devices[_ri(i, 0, 23)]['device_id'],
        'timestamp': _dt(2026, 5, 31, 6 + (i % 18), i % 59),
        'metric_name': _pick(metrics, i),
        'metric_val': _round2(_rnd(i) * 100),
      });
  final alerts = _range(30, (i) => <String, Object?>{
        'alert_id': i + 1,
        'device_id': devices[_ri(i, 0, 23)]['device_id'],
        'severity': _pick(['Info', 'Warning', 'Critical'], _ri(i, 0, 2)),
        'message': _pick(['Threshold exceeded', 'Device unreachable', 'Battery low', 'Calibration drift', 'Signal loss'], i),
        'raised_at': _dt(2026, 5, 30 - (i % 20) + 1, 10 + (i % 10), i % 59),
        'resolved': i % 3 == 0 ? 1 : 0,
      });
  final firmware = _range(8, (i) => <String, Object?>{
        'firmware_id': i + 1,
        'version': 'v${1 + (i % 3)}.$i.${_ri(i, 0, 9)}',
        'released': _date(2025, (i % 12) + 1, (i % 27) + 1),
        'critical': i % 4 == 0 ? 1 : 0,
      });
  final maintenance = _range(22, (i) => <String, Object?>{
        'ticket_id': i + 1,
        'device_id': devices[_ri(i, 0, 23)]['device_id'],
        'technician': '${_pick(_first, i)} ${_pick(_last, i)}',
        'scheduled': _date(2026, (i % 6) + 1, (i % 27) + 1),
        'status': _pick(['Open', 'Scheduled', 'Done'], i),
      });

  final t = <String, TableDef>{};
  t['devices'] = TableDef(name: 'devices', columns: [
    _col('device_id', 'VARCHAR(30)', pk: true, nullable: false),
    _col('device_name', 'VARCHAR(100)', nullable: false),
    _col('location', 'VARCHAR(100)'),
    _col('firmware_id', 'INT', fkTable: 'firmware', fkCol: 'firmware_id'),
    _col('status', 'VARCHAR(15)', nullable: false),
    _col('last_seen', 'DATETIME'),
  ], rows: devices);
  t['telemetry_logs'] = TableDef(name: 'telemetry_logs', columns: [
    _col('log_id', 'INT', pk: true, ai: true, nullable: false),
    _col('device_id', 'VARCHAR(30)', nullable: false, fkTable: 'devices', fkCol: 'device_id'),
    _col('timestamp', 'DATETIME', nullable: false),
    _col('metric_name', 'VARCHAR(40)', nullable: false),
    _col('metric_val', 'DOUBLE', nullable: false),
  ], rows: telemetryLogs);
  t['alerts'] = TableDef(name: 'alerts', columns: [
    _col('alert_id', 'INT', pk: true, ai: true, nullable: false),
    _col('device_id', 'VARCHAR(30)', nullable: false, fkTable: 'devices', fkCol: 'device_id'),
    _col('severity', 'VARCHAR(10)', nullable: false),
    _col('message', 'VARCHAR(120)'),
    _col('raised_at', 'DATETIME', nullable: false),
    _col('resolved', 'TINYINT(1)', nullable: false),
  ], rows: alerts);
  t['firmware'] = TableDef(name: 'firmware', columns: [
    _col('firmware_id', 'INT', pk: true, ai: true, nullable: false),
    _col('version', 'VARCHAR(20)', nullable: false),
    _col('released', 'DATE', nullable: false),
    _col('critical', 'TINYINT(1)', nullable: false),
  ], rows: firmware);
  t['maintenance'] = TableDef(name: 'maintenance', columns: [
    _col('ticket_id', 'INT', pk: true, ai: true, nullable: false),
    _col('device_id', 'VARCHAR(30)', nullable: false, fkTable: 'devices', fkCol: 'device_id'),
    _col('technician', 'VARCHAR(80)'),
    _col('scheduled', 'DATE'),
    _col('status', 'VARCHAR(15)', nullable: false),
  ], rows: maintenance);

  return Catalog(
    label: 'iot_telemetry',
    tables: t,
    views: [
      {'name': 'v_open_alerts', 'definition': 'CREATE VIEW v_open_alerts AS\nSELECT * FROM alerts WHERE resolved = 0 ORDER BY raised_at DESC;'},
    ],
    procedures: [],
    functions: [],
    triggers: [
      {'name': 'after_alert_resolved', 'event': 'AFTER UPDATE', 'target': 'alerts', 'definition': 'CREATE TRIGGER after_alert_resolved\nAFTER UPDATE ON alerts FOR EACH ROW\nBEGIN\n  -- log resolution\nEND'},
    ],
    er: {
      'firmware': const Offset2(24, 40), 'devices': const Offset2(252, 60), 'telemetry_logs': const Offset2(480, 40), 'alerts': const Offset2(480, 320), 'maintenance': const Offset2(252, 360),
    },
    relations: [
      Relation('devices', 'firmware', 'devices.firmware_id → firmware.firmware_id', 'lime'),
      Relation('telemetry_logs', 'devices', 'telemetry_logs.device_id → devices.device_id', 'info'),
      Relation('alerts', 'devices', 'alerts.device_id → devices.device_id', 'coral'),
      Relation('maintenance', 'devices', 'maintenance.device_id → devices.device_id', 'warn'),
    ],
  );
}

Catalog _saas() {
  const plansArr = [['Free', 0], ['Starter', 29], ['Team', 99], ['Business', 299], ['Enterprise', 999], ['Custom', 1500]];
  const seats = [1, 5, 20, 100, 500, 9999];
  final plans = _range(6, (i) => <String, Object?>{
        'plan_id': i + 1,
        'name': plansArr[i][0],
        'monthly_price': plansArr[i][1],
        'seats': seats[i],
        'active': 1,
      });
  final accounts = _range(40, (i) => <String, Object?>{
        'account_id': i + 1,
        'company': '${_pick(['Acme', 'Globex', 'Initrode', 'Umbrella', 'Hooli', 'Vehement', 'Massive Dynamic', 'Soylent', 'Vandelay', 'Wonka'], i)} ${_pick(['Inc', 'LLC', 'Group', 'Labs', 'Co'], i)}',
        'plan_id': _ri(i, 1, 6),
        'seats': _ri(i + 1, 1, 250),
        'mrr': _ri(i + 2, 0, 4000),
        'created_at': _dt(2024 + (i % 2), (i % 12) + 1, (i % 27) + 1),
        'country': _pick(_country, i),
      });
  final subscriptions = _range(50, (i) => <String, Object?>{
        'subscription_id': i + 1,
        'account_id': _ri(i, 1, 40),
        'plan_id': _ri(i, 1, 6),
        'status': _pick(['Active', 'Active', 'Trialing', 'Past Due', 'Canceled'], _ri(i, 0, 4)),
        'started': _date(2025, (i % 12) + 1, (i % 27) + 1),
        'renews': _date(2026, (i % 12) + 1, (i % 27) + 1),
      });
  final invoices = _range(70, (i) => <String, Object?>{
        'invoice_id': 7001 + i,
        'subscription_id': _ri(i, 1, 50),
        'amount': _round2((_ri(i + 1, 29, 999)).toDouble()),
        'status': _pick(['Paid', 'Paid', 'Paid', 'Open', 'Void'], _ri(i, 0, 4)),
        'issued': _date(2026, (i % 5) + 1, (i % 27) + 1),
      });
  final usageEvents = _range(200, (i) => <String, Object?>{
        'event_id': i + 1,
        'account_id': _ri(i, 1, 40),
        'event_type': _pick(['api_call', 'login', 'export', 'seat_added', 'webhook'], i),
        'quantity': _ri(i + 1, 1, 500),
        'occurred_at': _dt(2026, 5, (i % 27) + 1, i % 24, i % 59),
      });

  final t = <String, TableDef>{};
  t['plans'] = TableDef(name: 'plans', columns: [
    _col('plan_id', 'INT', pk: true, ai: true, nullable: false),
    _col('name', 'VARCHAR(40)', nullable: false),
    _col('monthly_price', 'DECIMAL(10,2)', nullable: false),
    _col('seats', 'INT', nullable: false),
    _col('active', 'TINYINT(1)', nullable: false),
  ], rows: plans);
  t['accounts'] = TableDef(name: 'accounts', columns: [
    _col('account_id', 'INT', pk: true, ai: true, nullable: false),
    _col('company', 'VARCHAR(80)', nullable: false),
    _col('plan_id', 'INT', nullable: false, fkTable: 'plans', fkCol: 'plan_id'),
    _col('seats', 'INT', nullable: false),
    _col('mrr', 'DECIMAL(10,2)', nullable: false),
    _col('created_at', 'DATETIME', nullable: false),
    _col('country', 'CHAR(2)'),
  ], rows: accounts);
  t['subscriptions'] = TableDef(name: 'subscriptions', columns: [
    _col('subscription_id', 'INT', pk: true, ai: true, nullable: false),
    _col('account_id', 'INT', nullable: false, fkTable: 'accounts', fkCol: 'account_id'),
    _col('plan_id', 'INT', nullable: false, fkTable: 'plans', fkCol: 'plan_id'),
    _col('status', 'VARCHAR(20)', nullable: false),
    _col('started', 'DATE', nullable: false),
    _col('renews', 'DATE'),
  ], rows: subscriptions);
  t['invoices'] = TableDef(name: 'invoices', columns: [
    _col('invoice_id', 'INT', pk: true, ai: true, nullable: false),
    _col('subscription_id', 'INT', nullable: false, fkTable: 'subscriptions', fkCol: 'subscription_id'),
    _col('amount', 'DECIMAL(10,2)', nullable: false),
    _col('status', 'VARCHAR(20)', nullable: false),
    _col('issued', 'DATE', nullable: false),
  ], rows: invoices);
  t['usage_events'] = TableDef(name: 'usage_events', columns: [
    _col('event_id', 'INT', pk: true, ai: true, nullable: false),
    _col('account_id', 'INT', nullable: false, fkTable: 'accounts', fkCol: 'account_id'),
    _col('event_type', 'VARCHAR(30)', nullable: false),
    _col('quantity', 'INT', nullable: false),
    _col('occurred_at', 'DATETIME', nullable: false),
  ], rows: usageEvents);

  return Catalog(
    label: 'saas_metrics',
    tables: t,
    views: [
      {'name': 'v_mrr_by_plan', 'definition': 'CREATE VIEW v_mrr_by_plan AS\nSELECT p.name, SUM(a.mrr) mrr\nFROM accounts a JOIN plans p ON a.plan_id = p.plan_id\nGROUP BY p.name;'},
      {'name': 'v_churn_risk', 'definition': "CREATE VIEW v_churn_risk AS\nSELECT * FROM subscriptions WHERE status IN ('Past Due','Trialing');"},
    ],
    procedures: [
      {'name': 'CloseMonth', 'params': '', 'definition': "CREATE PROCEDURE CloseMonth()\nBEGIN\n  UPDATE invoices SET status = 'Void' WHERE status = 'Open' AND issued < CURDATE() - INTERVAL 60 DAY;\nEND"},
    ],
    functions: [],
    triggers: [],
    er: {
      'plans': const Offset2(24, 60), 'accounts': const Offset2(252, 40), 'subscriptions': const Offset2(252, 320), 'invoices': const Offset2(480, 320), 'usage_events': const Offset2(480, 40),
    },
    relations: [
      Relation('accounts', 'plans', 'accounts.plan_id → plans.plan_id', 'accent'),
      Relation('subscriptions', 'accounts', 'subscriptions.account_id → accounts.account_id', 'lime'),
      Relation('subscriptions', 'plans', 'subscriptions.plan_id → plans.plan_id', 'warn'),
      Relation('invoices', 'subscriptions', 'invoices.subscription_id → subscriptions.subscription_id', 'info'),
      Relation('usage_events', 'accounts', 'usage_events.account_id → accounts.account_id', 'violet'),
    ],
  );
}

/// Build a fresh deep-copyable set of catalogs.
Map<String, Catalog> buildCatalogs() => {
      'e_commerce': _eCommerce(),
      'hr_analytics': _hrAnalytics(),
      'iot_telemetry': _iot(),
      'saas_metrics': _saas(),
    };

const List<String> kTags = ['blue', 'lime', 'coral', 'pink', 'tan', 'cyan', 'violet', 'slate'];
const List<String> kGroups = ['Production', 'Analytics', 'Staging', 'Local', 'Personal'];

Map<String, Object?> _opt(String engine, Map<String, Object?> o) =>
    {...defaultsFor(engine), ...o};

List<Profile> defaultProfiles() => [
      Profile(id: 1, name: 'Postgres · Local Docker', group: 'Local', engine: 'postgres', host: '127.0.0.1', port: 5432, user: 'postgres', env: 'local', color: 'blue', label: 'pg17', ssl: false, ssh: false, catalog: 'sqlpulse_demo', options: _opt('postgres', {'password': 'pass', 'pgSslMode': 'disable'})),
      Profile(id: 2, name: 'MySQL · Local Docker', group: 'Local', engine: 'mysql', host: '127.0.0.1', port: 3306, user: 'root', env: 'local', color: 'cyan', label: 'mysql8', ssl: true, ssh: false, catalog: 'sqlpulse_demo', options: _opt('mysql', {'password': 'pass'})),
      Profile(id: 3, name: 'MariaDB · Local Docker', group: 'Local', engine: 'mariadb', host: '127.0.0.1', port: 3309, user: 'root', env: 'local', color: 'tan', label: 'maria11', ssl: false, ssh: false, catalog: 'sqlpulse_demo', options: _opt('mariadb', {'password': 'pass'})),
      Profile(id: 4, name: 'SQL Server · Local Docker', group: 'Local', engine: 'mssql', host: '127.0.0.1', port: 1433, user: 'sa', env: 'local', color: 'coral', label: 'mssql2022', ssl: false, ssh: false, catalog: 'sqlpulse_demo', options: _opt('mssql', {'password': r'Str0ng!Passw0rd', 'encrypt': false, 'trustServerCert': true})),
      Profile(id: 5, name: 'SQLite · Sample File', group: 'Local', engine: 'sqlite', host: 'sample', port: 0, user: '', env: 'local', color: 'lime', label: 'file', ssl: false, ssh: false, catalog: 'main', options: _opt('sqlite', {'dbFile': 'sample'})),
    ];

const List<RoleDef> kRoles = [
  RoleDef('Admin', 'Admin', 'Full schema + data control', 'shield'),
  RoleDef('Developer', 'Developer', 'DDL + DML, no user mgmt', 'wrench'),
  RoleDef('Analyst', 'Analyst', 'Read + write rows, no DDL', 'chart'),
  RoleDef('ReadOnly', 'Read-only', 'Select statements only', 'eye'),
];

List<AuditEntry> defaultAudit() {
  final now = DateTime.now().millisecondsSinceEpoch;
  int mAgo(int n) => now - n * 60000;
  return [
    AuditEntry(role: 'Admin', status: 'SELECT', table: 'users', query: 'SELECT * FROM users LIMIT 10;', ms: 4, rows: 10, at: mAgo(2)),
    AuditEntry(role: 'Developer', status: 'DDL', table: 'products', query: 'ALTER TABLE products ADD INDEX idx_category (category_id);', ms: 31, rows: 0, at: mAgo(9)),
    AuditEntry(role: 'Analyst', status: 'SELECT', table: 'orders', query: 'SELECT u.username, o.total_amount FROM users u JOIN orders o ON u.id = o.user_id;', ms: 6, rows: 64, at: mAgo(14)),
    AuditEntry(role: 'ReadOnly', status: 'DENIED', table: 'users', query: 'DELETE FROM users WHERE id = 3;', ms: 1, rows: 0, at: mAgo(22)),
    AuditEntry(role: 'Admin', status: 'DML', table: 'orders', query: "UPDATE orders SET status = 'Shipped' WHERE order_id = 1004;", ms: 12, rows: 1, at: mAgo(38)),
    AuditEntry(role: 'Developer', status: 'SYNTAX', table: '', query: 'SELCT * FROM prodcts;', ms: 1, rows: 0, at: mAgo(51)),
    AuditEntry(role: 'Admin', status: 'CONNECT', table: '', query: 'CONNECT 10.0.1.42:3306 · SSL · SSH tunnel', ms: 120, rows: 0, at: mAgo(63)),
  ];
}
