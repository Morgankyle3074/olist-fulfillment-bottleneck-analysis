\copy orders FROM 'C:/Users/Kyle/Documents/SQl Datasets/hd-fulfillment-bottleneck/data/archive/olist_orders_dataset.csv' WITH (FORMAT csv, HEADER true);

\copy order_items FROM 'C:/Users/Kyle/Documents/SQl Datasets/hd-fulfillment-bottleneck/data/archive/olist_order_items_dataset.csv' WITH (FORMAT csv, HEADER true);

\copy products FROM 'C:/Users/Kyle/Documents/SQl Datasets/hd-fulfillment-bottleneck/data/archive/olist_products_dataset.csv' WITH (FORMAT csv, HEADER true);

\copy customers FROM 'C:/Users/Kyle/Documents/SQl Datasets/hd-fulfillment-bottleneck/data/archive/olist_customers_dataset.csv' WITH (FORMAT csv, HEADER true);

