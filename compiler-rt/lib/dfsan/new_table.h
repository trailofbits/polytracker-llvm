#include <sanitizer_common/sanitizer_allocator_internal.h>
#include <sanitizer_common/sanitizer_atomic.h>
#include <stdint.h>
#include "dfsan.h"

typedef uint64_t key_t;

/*
This is a bucket hash implementation 

===== B1
|   | <-- Cell 0
|   | <-- Cell 1
----- B2
|   | 
|   | 
----- B3
|   | 
|   | 
===== End

====== <-- Overflow List
|   | <-- Cell N
|   | <-- Cell N+1
|   | ....

Hash key into --> Bucket. Look for empty cell in bucket. If no empty cell, add to overflow list. 
Worst case, O(N), average case depends on hashing algo and bucket size.
*/

struct ListNode {
    ListNode* next;
    Cell cell;
};

struct OverFlowList {
    ListNode* head;
    // O(1) insertions
    ListNode* tail;
};

//Can template-ify later
struct Cell {
    key_t key;
    dfsan_label val; 
};

static const uint32_t kBucketSize = 30;

struct Bucket {
    Cell cells[kBucketSize];
};

struct TaintHash {
    Bucket * table;
    OverFlowList * list;
};