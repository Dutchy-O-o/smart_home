const { Client } = require('pg');

exports.handler = async (event) => {
    console.log("Event:", JSON.stringify(event));

    // // API Gateway Cognito Authorizer üzerinden UserId (sub) alınır.
    // Eger authorizer bagliysa, userId buradan gelir: event.requestContext.authorizer.claims.sub
    // Yerel test veya custom JWT aktarimi icin event.queryStringParameters da kullanılabilir
    let userId = null;
    
    if (event.requestContext && event.requestContext.authorizer && event.requestContext.authorizer.claims) {
        userId = event.requestContext.authorizer.claims.sub;
    } else if (event.queryStringParameters && event.queryStringParameters.userId) {
        userId = event.queryStringParameters.userId;
    }

    if (!userId) {
        return {
            statusCode: 400,
            headers: { 
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Credentials": true
            },
            body: JSON.stringify({ error: "Unauthorized veya Eksik User ID" }),
        };
    }

    const client = new Client({
        host: process.env.DB_HOST,
        user: process.env.DB_USER,
        password: process.env.DB_PASSWORD,
        database: process.env.DB_NAME,
        port: process.env.DB_PORT || 5432,
        ssl: { rejectUnauthorized: false } // Supabase/RDS/Neon icin genelde gerekir
    });

    try {
        await client.connect();
        
        // Stored Function'i cagiriyoruz
        const query = 'SELECT * FROM get_user_homes($1)';
        const res = await client.query(query, [userId]);
        
        await client.end();
        
        return {
            statusCode: 200,
            headers: { 
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Credentials": true,
                "Content-Type": "application/json"
            },
            body: JSON.stringify({ 
                success: true,
                userId: userId,
                homes: res.rows 
            }),
        };
        
    } catch (error) {
        console.error('Database hatasi:', error);
        
        try {
            await client.end();
        } catch (e) {
            console.error(e);
        }
        
        return {
            statusCode: 500,
            headers: { "Access-Control-Allow-Origin": "*" },
            body: JSON.stringify({ error: "Sunucu hatasi, evler listelenemedi.", details: error.message }),
        };
    }
};
