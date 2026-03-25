# Firebase Firestore Architecture Documentation

## 📋 Table of Contents
1. [Overview](#overview)
2. [Architecture Design](#architecture-design)
3. [Collection Structure](#collection-structure)
4. [Design Decisions & Rationale](#design-decisions--rationale)
5. [Advantages](#advantages)
6. [Scalability Considerations](#scalability-considerations)
7. [Security & Data Isolation](#security--data-isolation)
8. [Indexing Strategy](#indexing-strategy)
9. [Best Practices Followed](#best-practices-followed)

---

## Overview

This document outlines the Firebase Firestore database architecture for the Ledger Management System. The architecture is designed with **multi-tenancy**, **scalability**, and **maintainability** as core principles.

### Key Features
- ✅ **Multi-tenant architecture** - Each shop operates in complete data isolation
- ✅ **Hierarchical data organization** - Logical grouping using subcollections
- ✅ **Optimized querying** - Strategic use of indexes and collection groups
- ✅ **Scalable design** - Supports unlimited shops and transactions
- ✅ **Data integrity** - Proper relationships and referential structure

---

## Architecture Design

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Firebase Firestore                       │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────┐      ┌──────────────┐                    │
│  │ adminlogin   │      │  shop_list   │                    │
│  │ (Global)     │      │  (Global)     │                    │
│  └──────────────┘      └──────────────┘                    │
│                                                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │         Shop Collections (Per Tenant)                 │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────┐  │   │
│  │  │ abc_retails  │  │ vks_retails  │  │ shop_3   │  │   │
│  │  └──────────────┘  └──────────────┘  └──────────┘  │   │
│  │         │                  │                │         │   │
│  │    (Isolated Data per Shop)                          │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

### Multi-Tenancy Model

The system implements a **collection-per-tenant** model where each shop has its own dedicated collection. This ensures:
- Complete data isolation between shops
- Independent scaling per shop
- Simplified access control
- Easy data migration and backup

---

## Collection Structure

### 1. Global Collections

#### `adminlogin`
**Purpose**: Stores admin/client authentication credentials

**Structure**:
```
adminlogin/
  └── {documentId}/
      ├── username: string
      ├── password: string (hashed)
      └── updatedAt: timestamp
```

**Usage**: Admin login authentication for client-level access

---

#### `shop_list`
**Purpose**: Master registry of all shops in the system

**Structure**:
```
shop_list/
  └── {shopId}/
      ├── collectionName: string (e.g., "abc_retails")
      ├── shopName: string
      ├── location: string
      ├── phone: string
      ├── username: string
      ├── createdAt: timestamp
      └── status: string ("active" | "inactive")
```

**Usage**: 
- Shop selection for admin users
- Shop metadata management
- Reference for shop collection names

---

### 2. Shop-Specific Collections (Per Tenant)

Each shop has its own collection named using the pattern: `{shop_name}_retails` (e.g., `abc_retails`, `vks_retails`)

#### Structure Overview
```
{shop_collection}/
  ├── Credentials (document)
  ├── ledgers (document)
  │   ├── dates/ (subcollection)
  │   └── transactions/ (subcollection)
  └── customers (document)
      └── list/ (subcollection)
          └── {customerId}/
              └── transactions/ (subcollection)
```

---

#### 2.1 Credentials Document
**Path**: `{shop_collection}/Credentials`

**Structure**:
```json
{
  "shopName": "ABC Retails",
  "location": "Tanjore",
  "phone": "8778523095",
  "username": "abc@123",
  "password": "hashed_password",
  "createdAt": "timestamp",
  "status": "active"
}
```

**Purpose**: Employee authentication for shop-specific access

---

#### 2.2 Ledgers Structure
**Path**: `{shop_collection}/ledgers/`

##### 2.2.1 Dates Subcollection
**Path**: `{shop_collection}/ledgers/dates/{date}`

**Document ID Format**: `dd-MMM-yyyy` (e.g., `04-Dec-2025`)

**Structure**:
```json
{
  "ledgerDate": "04-Dec-2025",
  "openingBalance": 50000,
  "closingBalance": 75000,
  "saleValue": 0,
  "cashOut": 0,
  "denominations": {
    "2000": 10,
    "500": 20,
    "200": 15,
    "100": 30,
    "50": 40,
    "20": 50,
    "10": 100
  },
  "totals": [20000, 10000, 3000, 3000, 2000, 1000, 1000],
  "note": "Opening balance notes",
  "status": "Open" | "Closed",
  "createdAt": "timestamp",
  "createdBy": "Admin" | "Employee"
}
```

**Purpose**: Daily ledger entries with opening/closing balances

---

##### 2.2.2 Transactions Subcollection
**Path**: `{shop_collection}/ledgers/transactions/{transactionId}`

**Structure**:
```json
{
  "amount": 5000,
  "isCredit": false,
  "description": "Payment received from customer",
  "ledgerDate": "04-Dec-2025",
  "customerName": "John Doe",
  "ledgerName": "General Ledger",
  "transactionType": "Customer" | "General",
  "transactionDate": "04-Dec-2025",
  "billPhotoUrl": "gs://bucket/path/to/image.jpg",
  "createdAt": "timestamp"
}
```

**Purpose**: All transactions linked to ledgers, queryable by `ledgerDate`

**Query Patterns**:
- Get all transactions for a specific ledger date
- Filter by transaction type (Customer/General)
- Order by creation time

---

#### 2.3 Customers Structure
**Path**: `{shop_collection}/customers/`

##### 2.3.1 Customer List Subcollection
**Path**: `{shop_collection}/customers/list/{customerId}`

**Structure**:
```json
{
  "customerName": "John Doe",
  "customerType": "Retail" | "Wholesale",
  "mobileNumber": "9876543210",
  "openingAmount": 10000,
  "status": "Active" | "Inactive",
  "createdAt": "timestamp",
  "lastTransaction": "timestamp"
}
```

**Purpose**: Customer master data for each shop

---

##### 2.3.2 Customer Transactions Subcollection
**Path**: `{shop_collection}/customers/list/{customerId}/transactions/{transactionId}`

**Structure**:
```json
{
  "amount": 5000,
  "isCredit": false,
  "description": "Payment received",
  "ledgerDate": "04-Dec-2025",
  "billPhotoUrl": "gs://bucket/path/to/image.jpg",
  "createdAt": "timestamp"
}
```

**Purpose**: Customer-specific transaction history

**Benefits**:
- Quick access to customer transaction history
- Calculate outstanding balances per customer
- Isolated queries for customer analytics

---

## Design Decisions & Rationale

### 1. Collection-Per-Tenant Model

**Decision**: Each shop has its own top-level collection

**Rationale**:
- ✅ **Data Isolation**: Complete separation between shops
- ✅ **Security**: Easier to implement shop-level access control
- ✅ **Performance**: Queries are scoped to single collection
- ✅ **Scalability**: Each shop can scale independently
- ✅ **Backup/Migration**: Easy to backup or migrate individual shops

**Alternative Considered**: Single collection with `shopId` field
- ❌ Rejected due to: Complex queries, security rules, and potential performance issues at scale

---

### 2. Document-as-Container Pattern

**Decision**: Use documents (`ledgers`, `customers`) as containers for subcollections

**Rationale**:
- ✅ **Logical Grouping**: Related data grouped under parent document
- ✅ **Query Efficiency**: Subcollections can be queried independently
- ✅ **Flexibility**: Can store metadata in parent document if needed
- ✅ **Firestore Best Practice**: Recommended pattern for hierarchical data

**Example**:
```
ledgers (document) → dates (subcollection) → {date} (documents)
                 → transactions (subcollection) → {transactionId} (documents)
```

---

### 3. Date-Based Document IDs for Ledgers

**Decision**: Use `dd-MMM-yyyy` format as document ID for ledger dates

**Rationale**:
- ✅ **Human Readable**: Easy to identify in Firebase Console
- ✅ **Unique Constraint**: Natural uniqueness per date
- ✅ **Query Efficiency**: Direct document access without query
- ✅ **Sorting**: Can be sorted chronologically

**Alternative Considered**: Auto-generated IDs with date field
- ❌ Rejected due to: Need for additional queries and less intuitive structure

---

### 4. Dual Transaction Storage

**Decision**: Store transactions in both:
1. `ledgers/transactions` - For ledger-level queries
2. `customers/list/{id}/transactions` - For customer-level queries

**Rationale**:
- ✅ **Query Optimization**: Fast queries for both use cases
- ✅ **Data Locality**: Related data stored together
- ✅ **Analytics**: Easy to calculate customer balances and ledger totals
- ✅ **Flexibility**: Can query transactions from multiple perspectives

**Trade-off**: Slight data duplication, but significant query performance gain

---

## Advantages

### 1. **Multi-Tenancy Excellence**
- Complete data isolation per shop
- No cross-shop data leakage
- Independent scaling and management

### 2. **Query Performance**
- Subcollections enable targeted queries
- Indexed fields for fast lookups
- Minimal data scanning required

### 3. **Scalability**
- Supports unlimited shops
- Each shop collection scales independently
- No single collection bottleneck

### 4. **Maintainability**
- Clear, logical structure
- Easy to understand and navigate
- Self-documenting architecture

### 5. **Security**
- Shop-level access control
- Isolated data prevents unauthorized access
- Simple security rules implementation

### 6. **Flexibility**
- Easy to add new shops
- Can extend structure without breaking changes
- Supports future feature additions

---

## Scalability Considerations

### Current Capacity
- **Shops**: Unlimited (each is a separate collection)
- **Customers per Shop**: Unlimited (subcollection scales automatically)
- **Transactions per Shop**: Unlimited (Firestore handles millions of documents)
- **Ledgers per Shop**: ~365 per year (date-based, predictable growth)

### Performance Optimizations

1. **Indexed Queries**
   - Composite indexes for `ledgerDate + createdAt`
   - Single-field indexes for frequently queried fields

2. **Collection Group Queries**
   - `firestore.indexes.json` configured for cross-shop queries if needed
   - Optimized for transaction queries across collection groups

3. **Pagination**
   - Large result sets paginated using `limit()` and `startAfter()`
   - Prevents memory issues with large datasets

4. **Data Locality**
   - Related data stored together (subcollections)
   - Reduces query complexity and improves performance

### Growth Projections

| Metric | Year 1 | Year 5 | Notes |
|--------|--------|--------|-------|
| Shops | 10 | 100 | Linear growth |
| Customers/Shop | 100 | 500 | Per shop average |
| Transactions/Shop/Day | 50 | 200 | Daily average |
| Total Documents | ~200K | ~40M | Estimated |

**Conclusion**: Architecture can handle 10x growth without structural changes

---

## Security & Data Isolation

### Data Isolation Strategy

1. **Collection-Level Isolation**
   - Each shop has dedicated collection
   - No shared collections between shops
   - Prevents accidental data access

2. **Access Control**
   - Shop employees can only access their shop's collection
   - Admin users can access all shops via `shop_list`
   - Credentials stored per shop

3. **Security Rules (Recommended)**
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Shop-specific collections
    match /{shopCollection}/{document=**} {
      allow read, write: if request.auth != null 
        && get(/databases/$(database)/documents/$(shopCollection)/Credentials).data.username == request.auth.token.email;
    }
    
    // Global collections
    match /shop_list/{document} {
      allow read: if request.auth != null;
      allow write: if request.auth.token.admin == true;
    }
    
    match /adminlogin/{document} {
      allow read, write: if request.auth.token.admin == true;
    }
  }
}
```

---

## Indexing Strategy

### Composite Indexes

Defined in `firestore.indexes.json`:

```json
{
  "indexes": [
    {
      "collectionGroup": "transactions",
      "queryScope": "Collection",
      "fields": [
        {
          "fieldPath": "ledgerDate",
          "order": "ASCENDING"
        },
        {
          "fieldPath": "createdAt",
          "order": "DESCENDING"
        }
      ]
    }
  ]
}
```

### Index Usage

1. **Transaction Queries by Date**
   - `ledgerDate` + `createdAt` composite index
   - Enables efficient date-range queries

2. **Customer Transaction History**
   - Single-field index on `createdAt`
   - Fast chronological ordering

3. **Ledger Date Lookups**
   - Direct document access (no index needed)
   - O(1) lookup performance

### Index Deployment

Deploy indexes using:
```bash
firebase deploy --only firestore:indexes
```

---

## Best Practices Followed

### ✅ 1. Hierarchical Data Organization
- Used subcollections for related data
- Logical parent-child relationships
- Follows Firestore recommended patterns

### ✅ 2. Document Size Management
- Documents kept under 1MB limit
- Large data (images) stored in Firebase Storage
- Only references stored in Firestore

### ✅ 3. Query Optimization
- Indexed all frequently queried fields
- Used composite indexes for multi-field queries
- Avoided unnecessary data fetching

### ✅ 4. Naming Conventions
- Consistent collection naming (`{shop}_retails`)
- Clear document ID patterns (`dd-MMM-yyyy`)
- Descriptive field names

### ✅ 5. Timestamp Management
- Used `FieldValue.serverTimestamp()` for consistency
- Stored timestamps for audit trails
- Proper date formatting for queries

### ✅ 6. Data Relationships
- Maintained referential integrity
- Used document references where appropriate
- Denormalized for query performance

### ✅ 7. Error Handling
- Proper error handling in queries
- Fallback values for missing data
- Graceful degradation

---

## Data Flow Examples

### Example 1: Creating a Transaction

```
1. User creates transaction for customer "John Doe"
2. Transaction saved to:
   a. {shop_collection}/ledgers/transactions/{transactionId}
   b. {shop_collection}/customers/list/{customerId}/transactions/{transactionId}
3. Customer document updated: lastTransaction timestamp
4. Ledger closing balance recalculated (if ledger open)
```

### Example 2: Querying Customer Balance

```
1. Query: {shop_collection}/customers/list/{customerId}
2. Get openingAmount from customer document
3. Query: {shop_collection}/customers/list/{customerId}/transactions
4. Calculate: openingAmount + sum(paymentIn) - sum(paymentOut)
5. Return outstanding balance
```

### Example 3: Generating Ledger Report

```
1. Query: {shop_collection}/ledgers/dates/{date}
2. Get ledger document (openingBalance, closingBalance)
3. Query: {shop_collection}/ledgers/transactions
   - Filter: ledgerDate == {date}
4. Aggregate transactions
5. Generate PDF with all data
```

---

## Migration & Backup Strategy

### Backup Process

1. **Per-Shop Backup**
   - Export entire shop collection
   - Includes all subcollections
   - JSON format for portability

2. **Selective Backup**
   - Backup specific date ranges
   - Customer-specific backups
   - Transaction history backups

### Migration Path

If needed to restructure:
1. Export existing data
2. Transform to new structure
3. Import to new collections
4. Verify data integrity
5. Update application code

---

## Conclusion

This Firebase Firestore architecture demonstrates:

✅ **Professional Design** - Follows industry best practices  
✅ **Scalability** - Handles growth without restructuring  
✅ **Performance** - Optimized queries and indexes  
✅ **Security** - Proper data isolation and access control  
✅ **Maintainability** - Clear, logical structure  
✅ **Flexibility** - Easy to extend and modify  

The architecture is **production-ready** and designed to scale with business growth while maintaining data integrity and performance.

---

## Technical Specifications

- **Database**: Firebase Firestore (NoSQL)
- **Storage**: Firebase Storage (for bill images)
- **Functions**: Cloud Functions (for PDF generation)
- **Indexing**: Composite indexes for optimized queries
- **Multi-tenancy**: Collection-per-tenant model
- **Data Model**: Hierarchical with subcollections

---

**Document Version**: 1.0  
**Last Updated**: December 2025  
**Maintained By**: Development Team

